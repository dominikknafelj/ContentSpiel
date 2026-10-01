require "test_helper"

# `Admin::DashboardScreen::QuickCreateComponent` (dashboard spec §4.1): the
# draft form (only with a creatable type to offer), New page and Upload
# image, each shown only to someone who could use it.
class Admin::DashboardScreen::QuickCreateComponentTest < ViewComponent::TestCase
  teardown { Current.reset }

  test "an owner gets the form with every registered type, New page and Upload image" do
    Current.actor = users(:one)
    render_inline Admin::DashboardScreen::QuickCreateComponent.new

    assert_selector "form[action='/cs-studio/dashboard/draft'] input[name=title]"
    assert_equal ContentTypes.all.map(&:label), page.all("select[name=content_type] option").map(&:text)
    assert_selector "a", text: "New page"
    assert_selector "a", text: "Upload image"
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
