require "test_helper"

class Admin::Ui::SaveBarComponentTest < ViewComponent::TestCase
  test "the bar floats: the popover ground, the card radius, elevation 3, and Discard before Save changes" do
    render_inline(Admin::Ui::SaveBarComponent.new(form_id: "user-form", cancel_url: "/users"))

    assert_selector ".admin-save-bar.admin-save-bar--floating.sticky.bg-popover.rounded-card.shadow-3.px-4.py-3[class~='bottom-(--cs-sp-3)'][class~='z-(--cs-z-sticky)'][data-admin--saving--save-bar-target=bar]"
    assert_no_selector ".admin-save-bar.border-t, .admin-save-bar.bg-paper, .admin-save-bar[data-stuck]"
    assert_no_selector ".admin-save-bar[hidden]", visible: :all
    # The 8px accent dot, hidden until something is unsaved.
    assert_selector ".admin-save-bar [data-admin--saving--save-bar-target=dot][aria-hidden=true].size-2.rounded-full.bg-accent[hidden]", visible: :all
    assert_selector "[data-admin--saving--save-bar-target=count][aria-live=polite]", visible: :all
    assert_selector "a[href='/users']", text: "Discard"
    assert_selector "button[type=submit][form='user-form'][data-admin--saving--save-bar-target=save]", text: "Save changes"
  end

  # Discard is a link into the content frame, and the one such link the leave
  # guard lets through without asking (`admin--saving--save-bar` looks for the marker).
  test "Discard keeps the marker that exempts it from the leave guard" do
    render_inline(Admin::Ui::SaveBarComponent.new(form_id: "user-form", cancel_url: "/users"))
    assert_selector "a[href='/users'][data-save-bar-cancel][data-turbo-frame=content]", text: "Discard"
  end

  # The words come first and the buttons stand together at the bar's end,
  # the primary last.
  test "the count comes first, then Discard, then Save at the end" do
    render_inline(Admin::Ui::SaveBarComponent.new(form_id: "user-form", cancel_url: "/users"))
    parts = page.all(".admin-save-bar [data-admin--saving--save-bar-target=count], .admin-save-bar a, .admin-save-bar button", visible: :all)
      .map { |node| node["data-admin--saving--save-bar-target"] == "count" ? "count" : node.text }
    assert_equal [ "count", "Discard", "Save changes" ], parts
  end

  test "a screen's own Save label is kept" do
    render_inline(Admin::Ui::SaveBarComponent.new(form_id: "group-form", cancel_url: "/groups", save_label: "Save group"))
    assert_selector "button[type=submit][form='group-form']", text: /\ASave group\z/
  end

  # Nothing server-rendered disables Save: only the controller does, so the
  # form can still be submitted when JavaScript never runs.
  test "Save is a working submit button without JavaScript" do
    render_inline(Admin::Ui::SaveBarComponent.new(form_id: "user-form", cancel_url: "/users"))
    assert_selector "button[type=submit][form='user-form']:not([disabled])", text: "Save changes"
    assert_no_selector "noscript", visible: :all
  end

  test "save_label and save_data reach the Save button" do
    render_inline(Admin::Ui::SaveBarComponent.new(form_id: "f", cancel_url: "/x", save_label: "Save group", save_data: { password_submit: true }))
    assert_selector "button[type=submit][data-password-submit][data-admin--saving--save-bar-target=save]", text: "Save group"
  end

  # The footer of one card, inside it: under a line, within the card's
  # padding, not stuck to the window, and with no dot. It says Discard too.
  test "a contained bar keeps its look and says Discard" do
    render_inline(Admin::Ui::SaveBarComponent.new(form_id: "f", cancel_url: "/x", save_label: "Change password", contained: true))
    assert_selector ".admin-save-bar.admin-save-bar--contained.border-t.border-line[data-admin--saving--save-bar-target=bar]"
    assert_no_selector ".admin-save-bar.sticky, .admin-save-bar.bg-popover, .admin-save-bar.shadow-3, .admin-save-bar--floating"
    assert_no_selector "[data-admin--saving--save-bar-target=dot]", visible: :all
    assert_selector ".admin-save-bar[class~='px-4'] button[type=submit][form=f][data-admin--saving--save-bar-target=save]", text: "Change password"
    assert_selector ".admin-save-bar a[data-save-bar-cancel]", text: "Discard"
    assert_selector ".admin-save-bar [data-admin--saving--save-bar-target=count][aria-live=polite].text-small", visible: :all
    assert_selector ".admin-save-bar [data-admin--saving--save-bar-target=blocked].text-small", visible: :all
  end
end
