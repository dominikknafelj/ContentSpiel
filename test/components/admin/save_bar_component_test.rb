require "test_helper"

class Admin::SaveBarComponentTest < ViewComponent::TestCase
  test "a hidden sticky bar with a live count, Cancel and Save" do
    render_inline(Admin::SaveBarComponent.new(form_id: "user-form", cancel_url: "/users"))
    assert_selector ".admin-save-bar[hidden][data-admin--save-bar-target=bar]", visible: :all
    assert_selector "[data-admin--save-bar-target=count][aria-live=polite]", visible: :all
    assert_selector "a[href='/users']", text: "Cancel", visible: :all
    assert_selector "button[type=submit][form='user-form']", text: "Save", visible: :all
  end

  # The bar is hidden until the controller shows it: without JavaScript the
  # form still needs a way to be submitted.
  test "a noscript Save stands in when the controller never runs" do
    render_inline(Admin::SaveBarComponent.new(form_id: "user-form", cancel_url: "/users", save_label: "Save changes"))
    noscript = Nokogiri::HTML5.fragment(rendered_content.to_s[%r{<noscript>(.*)</noscript>}m, 1])
    assert_equal 1, noscript.css("button[type=submit][form='user-form']").size
    assert_equal "Save changes", noscript.text.strip
  end

  test "save_label and save_data reach the Save button" do
    render_inline(Admin::SaveBarComponent.new(form_id: "f", cancel_url: "/x", save_label: "Save group", save_data: { password_submit: true }))
    assert_selector "button[type=submit][data-password-submit]", text: "Save group", visible: :all
  end
end
