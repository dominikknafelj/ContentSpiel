require "test_helper"

class Admin::EditorScreen::DeleteBlockDialogComponentTest < ViewComponent::TestCase
  include ContentHelper

  def dialog(owner)
    block = owner.content_blocks.create!(block_type: "rich_text", position: 0)
    as(users(:one)) { render_inline Admin::EditorScreen::DeleteBlockDialogComponent.new(page: owner, block: block) }
  end

  test "on a live page the delete dialog says its notes do not come back with a discard; on a draft it does not" do
    dialog(create_page(title: "Live"))
    assert_text "Blocks don’t go to the trash. This can’t be undone. Its notes are deleted with it and do not come back if the changes are discarded."

    dialog(create_page(title: "Draft", published: false))
    assert_text "Blocks don’t go to the trash. This can’t be undone."
    assert_no_text "do not come back if the changes are discarded"
  end

  test "a scheduled page says it too: its changes can be discarded as well" do
    scheduled = create_page(title: "Later", published: false)
    assert as(users(:one)) { Pages::Save.call(scheduled, attributes: { published_at: 3.days.from_now }) }.ok?

    dialog(scheduled.reload)

    assert_text "do not come back if the changes are discarded"
  end
end
