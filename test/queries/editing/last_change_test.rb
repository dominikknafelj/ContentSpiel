require "test_helper"

class Editing::LastChangeTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing", published: false)
    @block = as(users(:one), channel: :admin) { ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "image" }).record }
  end

  test "the newest change by someone else is named, with its time" do
    travel(1.minute) { as(users(:two), channel: :admin) { assert ContentBlocks::Save.call(@block, translations: { "en" => { caption: "x" } }).ok? } }

    change = Editing::LastChange.for(@block, viewer: users(:one))

    assert_equal users(:two), change.user
    assert_in_delta 1.minute.from_now.to_f, change.at.to_f, 2
  end

  test "the viewer's own newest change is no change to tell them about, and a block nobody changed has none" do
    assert_nil Editing::LastChange.for(@block, viewer: users(:one))
    assert_nil Editing::LastChange.for(ContentBlock.new, viewer: users(:one))
  end

  test "a note and a take-over on the block are not changes" do
    as(users(:two), channel: :admin) { Audit.record("note.started", subject: @block, snapshot: nil) }

    assert_nil Editing::LastChange.for(@block, viewer: users(:one))
  end

  test "it is two statements at most: the event, and its user" do
    viewer = users(:two) # the fixture's own lookup is not the query's

    assert_operator capture_sql { Editing::LastChange.for(@block, viewer: viewer) }.size, :<=, 2
  end
end
