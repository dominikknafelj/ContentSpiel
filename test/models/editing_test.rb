require "test_helper"

class EditingTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing", published: false)
    @block = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }).record
  end

  test "the timings are ordered: a pass-over comes before a hold ends, and the sweep after" do
    assert_operator Editing::PASS_OVER, :<, Editing::HOLD
    assert_operator Editing::SWEEP_AFTER, :>, Editing::HOLD
  end

  test "a request names the record itself without a block id, a block of this page with one, and nothing else" do
    other_block = ContentBlocks::Save.call(ContentBlock.new(owner: create_page(title: "Other", published: false)), attributes: { block_type: "rich_text" }).record
    post = create_post(title: "News", published: false)

    assert_equal @page, Editing.subject_of(@page, nil)
    assert_equal @page, Editing.subject_of(@page, "")
    assert_equal @block, Editing.subject_of(@page, @block.id)
    assert_equal @block, Editing.subject_of(@page, @block.id.to_s)
    assert_nil Editing.subject_of(@page, other_block.id)
    assert_nil Editing.subject_of(@page, "abc")
    assert_equal post, Editing.subject_of(post, nil)
    assert_nil Editing.subject_of(post, @block.id)
  end

  test "a subject's name in the page" do
    assert_equal "block-#{@block.id}", Editing.key(@block)
    assert_equal "record", Editing.key(@page)
  end
end
