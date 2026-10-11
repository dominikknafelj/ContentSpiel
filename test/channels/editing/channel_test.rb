require "test_helper"

class Editing::ChannelTest < ActionCable::Channel::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @stranger = User.create!(email_address: "stranger@example.com", password: "a-long-password-1")
  end

  def connect_as(user) = stub_connection(current_user: user, session_id: user.sessions.create!.id)

  test "a reader is subscribed to the record's stream, built from the record that was found" do
    connect_as users(:reader)
    subscribe type: "page", id: @page.id

    assert subscription.confirmed?
    assert_has_stream "editing:record:Page-#{@page.id}"
  end

  test "a record out of scope, a trashed one, an unknown kind and a bad id are rejected alike" do
    connect_as @stranger
    subscribe type: "page", id: @page.id
    assert subscription.rejected?

    connect_as users(:one)
    assert Trash::Move.call(@page).ok?
    [ { type: "page", id: @page.id }, { type: "tag", id: 1 }, { type: "page", id: "1 OR 1=1" } ].each do |params|
      subscribe(**params)
      assert subscription.rejected?, params.inspect
    end
  end

  test "a library image has no stream to subscribe to" do
    connect_as users(:one)
    subscribe type: "media", id: create_media_asset.id

    assert subscription.rejected?
  end

  test "a post is accepted through the read scope" do
    connect_as users(:reader)
    post = create_post(title: "News")
    subscribe type: "post", id: post.id

    assert subscription.confirmed?
    assert_has_stream "editing:record:Post-#{post.id}"
  end

  test "the channel offers a client no action" do
    assert_empty Editing::Channel.action_methods.to_a
  end
end
