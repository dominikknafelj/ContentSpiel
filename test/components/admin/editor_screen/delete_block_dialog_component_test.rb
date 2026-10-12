require "test_helper"

class Admin::EditorScreen::DeleteBlockDialogComponentTest < ViewComponent::TestCase
  include ContentHelper

  def dialog(owner)
    block = owner.content_blocks.create!(block_type: "rich_text", position: 0)
    as(users(:one)) { render_inline Admin::EditorScreen::DeleteBlockDialogComponent.new(page: owner, block: block) }
  end

  LIVE = "Blocks don’t go to the trash. The block is removed from the site only when the changes are published; until then “Discard changes…” brings it back. Its notes are deleted now and do not come back.".freeze

  # A hand test found the live page's dialog saying "This can't be undone"
  # above a header whose "Discard changes…" undoes exactly that.
  test "on a live page the dialog says the block leaves the site only with a publish and comes back with a discard, its notes not; a draft's says it can't be undone" do
    dialog(create_page(title: "Live"))
    assert_text LIVE
    assert_no_text "This can’t be undone"

    dialog(create_page(title: "Draft", published: false))
    assert_text "Blocks don’t go to the trash. This can’t be undone."
    assert_no_text "Discard changes"
    assert_no_text "do not come back"
  end

  test "a scheduled page says it too: its changes can be discarded as well" do
    scheduled = create_page(title: "Later", published: false)
    assert as(users(:one)) { Pages::Save.call(scheduled, attributes: { published_at: 3.days.from_now }) }.ok?

    dialog(scheduled.reload)

    assert_text LIVE
    assert_no_text "This can’t be undone"
  end
end
