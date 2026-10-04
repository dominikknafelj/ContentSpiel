require "test_helper"

class Admin::SettingsFormComponentTest < ViewComponent::TestCase
  setup { Current.actor = users(:one) }

  test "the retention input is narrow, with its unit beside it and the explanation below as help" do
    render_inline Admin::SettingsFormComponent.new(site_setting: SiteSetting.instance)

    assert_selector "input[name$='[trash_retention_days]'].w-18[aria-describedby$='trash_retention_days_help']"
    assert_selector "[id$='trash_retention_days_help']", text: "Items in the trash are deleted for good after this many days. 0 keeps them until you empty the trash."
    assert_no_text "days (0 = never)"
  end
end
