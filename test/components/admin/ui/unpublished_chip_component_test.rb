require "test_helper"

class Admin::Ui::UnpublishedChipComponentTest < ViewComponent::TestCase
  test "full: the label in the chip, with a warn dot a screen reader skips" do
    render_inline(Admin::Ui::UnpublishedChipComponent.new)

    assert_selector "span[data-unpublished-changes].border-line-strong", text: "Unpublished changes"
    assert_selector "span[data-unpublished-changes] span.bg-warn[aria-hidden=true]"
  end

  test "compact: a dot named for a screen reader and in a tooltip" do
    render_inline(Admin::Ui::UnpublishedChipComponent.new(compact: true))

    assert_selector "span[data-unpublished-changes][role=img][aria-label='Unpublished changes'][title='Unpublished changes'].bg-warn"
    assert_no_text "Unpublished changes"
  end
end
