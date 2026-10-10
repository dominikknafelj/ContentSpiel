require "test_helper"

class Admin::SaveBarComponentTest < ViewComponent::TestCase
  test "a visible sticky footer with Save, Cancel and a live count" do
    render_inline(Admin::SaveBarComponent.new(form_id: "user-form", cancel_url: "/users"))
    assert_selector ".admin-save-bar.sticky[data-admin--save-bar-target=bar]"
    assert_no_selector ".admin-save-bar[hidden]", visible: :all
    assert_selector "[data-admin--save-bar-target=count][aria-live=polite]", visible: :all
    assert_selector "a[href='/users']", text: "Cancel"
    assert_selector "button[type=submit][form='user-form'][data-admin--save-bar-target=save]", text: "Save"
  end

  # Cancel is a link into the content frame, and the one such link the leave
  # guard lets through without asking (`admin--save-bar` looks for the marker).
  test "Cancel carries the marker that exempts it from the leave guard" do
    render_inline(Admin::SaveBarComponent.new(form_id: "user-form", cancel_url: "/users"))
    assert_selector "a[href='/users'][data-save-bar-cancel][data-turbo-frame=content]", text: "Cancel"
  end

  # Save comes first, then Cancel, then the count: the buttons sit where the
  # form's fields end, not at the far side of the screen.
  test "Save comes before Cancel" do
    render_inline(Admin::SaveBarComponent.new(form_id: "user-form", cancel_url: "/users"))
    labels = page.all(".admin-save-bar button, .admin-save-bar a").map(&:text)
    assert_equal %w[Save Cancel], labels
  end

  # Nothing server-rendered disables Save: only the controller does, so the
  # form can still be submitted when JavaScript never runs.
  test "Save is a working submit button without JavaScript" do
    render_inline(Admin::SaveBarComponent.new(form_id: "user-form", cancel_url: "/users", save_label: "Save changes"))
    assert_selector "button[type=submit][form='user-form']:not([disabled])", text: "Save changes"
    assert_no_selector "noscript", visible: :all
  end

  test "save_label and save_data reach the Save button" do
    render_inline(Admin::SaveBarComponent.new(form_id: "f", cancel_url: "/x", save_label: "Save group", save_data: { password_submit: true }))
    assert_selector "button[type=submit][data-password-submit][data-admin--save-bar-target=save]", text: "Save group"
  end

  # The footer of one card, inside it (notes handoff, decision 34): under a
  # line, within the card's padding, not stuck to the window. The same parts.
  test "contained: the same footer inside a card, not sticky; the default is unchanged" do
    render_inline(Admin::SaveBarComponent.new(form_id: "f", cancel_url: "/x", save_label: "Change password", contained: true))
    assert_selector ".admin-save-bar.admin-save-bar--contained.border-t.border-line[data-admin--save-bar-target=bar]"
    assert_no_selector ".admin-save-bar.sticky, .admin-save-bar.bg-paper, .admin-save-bar.mt-6"
    assert_selector ".admin-save-bar[class~='px-[18px]'] button[type=submit][form=f][data-admin--save-bar-target=save]", text: "Change password"
    assert_selector ".admin-save-bar a[data-save-bar-cancel]", text: "Cancel"
    assert_selector ".admin-save-bar [data-admin--save-bar-target=count][aria-live=polite]", visible: :all

    render_inline(Admin::SaveBarComponent.new(form_id: "f", cancel_url: "/x"))
    assert_selector ".admin-save-bar.sticky.bottom-0.z-20.mt-6.bg-paper.py-3:not(.admin-save-bar--contained)"
  end
end
