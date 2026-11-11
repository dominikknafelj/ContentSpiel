require "test_helper"

class Admin::Ui::UnpublishedChipComponentTest < ViewComponent::TestCase
  test "full: the label in the chip, with a warn dot a screen reader skips" do
    render_inline(Admin::Ui::UnpublishedChipComponent.new)

    assert_selector "span[data-unpublished-changes].rounded-cs.border.border-field-line.bg-transparent.text-dim", text: "Unpublished changes"
    assert_selector "span[data-unpublished-changes] span.bg-warn[aria-hidden=true]"
  end

  test "its classes are the ones it spelled by hand, now read from the status chip's shell and Draft outline, without the status hook" do
    render_inline(Admin::Ui::UnpublishedChipComponent.new)
    before = "inline-flex shrink-0 items-center gap-1.5 rounded-cs border border-field-line bg-transparent px-2 py-0.5 text-xs text-dim"

    assert_equal before.split.sort, page.find("span[data-unpublished-changes]")[:class].split.sort
    assert_no_selector ".admin-status-chip"

    render_inline(Admin::Ui::StatusChipComponent.new(status: "draft"))
    draft = page.find(".admin-status-chip")[:class].split
    assert_equal %w[admin-status-chip], draft - before.split, "the Draft chip is the same shell and outline, with its hook"
  end

  test "there is no compact mode any more: the tree draws its own mark" do
    assert_raises(ArgumentError) { Admin::Ui::UnpublishedChipComponent.new(compact: true) }
  end
end
