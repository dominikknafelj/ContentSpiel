require "test_helper"

# `Admin::DashboardScreen::QuickCreateComponent` (dashboard spec §4.1): the
# draft form (only with a creatable type to offer), New page and Upload
# image, each shown only to someone who could use it.
class Admin::DashboardScreen::QuickCreateComponentTest < ViewComponent::TestCase
  teardown { Current.reset }

  test "an owner gets one row: title, a type select ending with Page, and Create draft; no New page or Upload image buttons" do
    Current.actor = users(:one)
    render_inline Admin::DashboardScreen::QuickCreateComponent.new

    assert_selector "form[action='/cs-studio/dashboard/draft'] input[name=title]"
    assert_equal ContentTypes.all.map(&:label) + [ "Page" ], page.all("select[name=content_type] option").map(&:text)
    assert_selector "option[value=page]"
    assert_selector "button", text: "Create draft"
    assert_no_text "Upload image"
    assert_selector "a[hidden][data-admin--dialog-id-param=new-page-dialog]", visible: :all
    assert_no_selector "a:not([hidden])"
  end

  test "Page is offered only with pages.create" do
    group = AccessControl::Group.create!(name: "Posters")
    group.grants.create!(permission: "posts.read", scope: {})
    group.grants.create!(permission: "posts.create", scope: {})
    user = User.create!(email_address: "poster@example.com", password: "password12345")
    AccessControl::Membership.create!(user:, group:)
    Current.actor = user
    render_inline Admin::DashboardScreen::QuickCreateComponent.new

    assert_no_selector "option[value=page]"
    assert_selector "option[value=blog]"
  end

  test "keeps the typed title, the chosen type and the error after a failed save" do
    Current.actor = users(:one)
    render_inline Admin::DashboardScreen::QuickCreateComponent.new(title: "Half", content_type: "now_update", errors: [ "Title can't be blank" ])

    assert_selector "input[name=title][value=Half]"
    assert_selector "select[name=content_type] option[selected][value=now_update]"
    assert_selector "[role=alert]", text: "Title can't be blank"
  end

  test "renders nothing for someone who can create nothing" do
    Current.actor = users(:reader)
    render_inline Admin::DashboardScreen::QuickCreateComponent.new

    assert_no_selector "form"
    assert_no_selector "a"
  end
end
