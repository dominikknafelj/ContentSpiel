require "test_helper"

class Notes::DeleteMessageTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @thread = as(users(:reader)) { Notes::Start.call(@page, body: "First") }.record
    @reply = travel_to(1.minute.from_now) { as(users(:two)) { Notes::Reply.call(@thread, body: "Second, @[#{users(:reader).id}]") } }.record
  end

  def delete(message, as_user:) = as(as_user) { Notes::DeleteMessage.call(message) }

  test "the author deletes their own message; its deliveries go, the thread stays and is dated by what is left" do
    result = delete(@reply, as_user: users(:two))

    assert result.ok?, result.errors.to_sentence
    assert_equal @thread, result.record
    assert_equal [ "First" ], @thread.reload.messages.map(&:body)
    assert_equal @thread.first_message.created_at.to_i, @thread.last_message_at.to_i
    assert_equal 0, Notes::Delivery.where(message_id: @reply.id).count
    event = Audit::Event.order(:id).last
    assert_equal [ "note.deleted", "Page", @page.id, { "thread_id" => @thread.id, "message_id" => @reply.id } ],
      [ event.action, event.subject_type, event.subject_id, event.metadata ]
  end

  test "deleting the last message deletes the thread" do
    delete(@reply, as_user: users(:two))
    result = delete(@thread.first_message, as_user: users(:reader))

    assert result.ok?
    assert_nil result.record
    assert_equal [ 0, 0, 0 ], [ Notes::Thread.count, Notes::Message.count, Notes::Follow.count ]
  end

  test "someone who may edit the page deletes another person's note; a reader may not" do
    assert delete(@thread.first_message, as_user: users(:two)).ok?

    result = delete(@reply, as_user: users(:reader))
    assert_predicate result, :denied?
    assert_equal "pages.edit", Audit::Event.order(:id).last.metadata["permission"]
    assert Notes::Message.exists?(@reply.id)
  end

  test "an image's uploader moderates the notes on it" do
    AccessControl::Grant.find_or_create_by!(group: access_control_groups(:author), permission: "media.upload") { |grant| grant.scope = {} }
    asset = create_media_asset
    asset.update_columns(created_by_id: users(:author).id)
    message = as(users(:two)) { Notes::Start.call(asset, body: "Crop it") }.record.first_message

    assert delete(message, as_user: users(:author)).ok?
  end

  test "a message already deleted is a success with nothing recorded" do
    stale = Notes::Message.find(@reply.id)
    @reply.destroy!

    assert_no_difference -> { Audit::Event.count } do
      assert delete(stale, as_user: users(:two)).ok?
    end
  end
end
