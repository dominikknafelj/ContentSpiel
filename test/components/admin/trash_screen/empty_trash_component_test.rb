require "test_helper"

# "Empty trash…" and its dialog: a sentence built from the kinds present, the
# counts being what `Trash::Empty` deletes; only for `trash.empty`, and only
# while something is in the trash.
class Admin::TrashScreen::EmptyTrashComponentTest < ViewComponent::TestCase
  teardown { Current.reset }

  test "names only the kinds present" do
    render_inline empty(pages: 0, subpages: 0, posts: 2, images: 0)
    assert_selector "dialog#empty-trash-dialog", text: "This deletes 2 posts for good. It can't be undone."

    render_inline empty(pages: 1, subpages: 0, posts: 0, images: 3)
    assert_selector "dialog#empty-trash-dialog", text: "This deletes 1 page and 3 images for good."

    render_inline empty(pages: 2, subpages: 0, posts: 1, images: 1)
    assert_selector "dialog#empty-trash-dialog", text: "This deletes 2 pages, 1 post and 1 image for good."
  end

  test "says how many subpages go with the page branches" do
    render_inline empty(pages: 1, subpages: 1, posts: 1, images: 1)
    assert_selector "dialog#empty-trash-dialog", text: "This deletes 1 page (with 1 subpage), 1 post and 1 image for good."
  end

  test "the header button and the destructive confirm" do
    render_inline empty(pages: 1, subpages: 0, posts: 0, images: 0)
    assert_selector "button", text: "Empty trash…"
    assert_selector "dialog#empty-trash-dialog", text: "Empty the trash?"
    assert_selector "dialog form[action='/cs-studio/trash'] input[name=_method][value=delete]", visible: :all
    assert_selector "dialog form button", text: "Empty trash"
  end

  test "renders nothing for an empty trash, or without trash.empty" do
    render_inline empty(pages: 0, subpages: 0, posts: 0, images: 0)
    assert_no_selector "button"

    Current.actor = users(:reader)
    render_inline empty(pages: 1, subpages: 0, posts: 0, images: 0)
    assert_no_selector "button"
  end

  private

  def empty(pages:, subpages:, posts:, images:)
    Admin::TrashScreen::EmptyTrashComponent.new(pages:, subpages:, posts:, images:)
  end
end
