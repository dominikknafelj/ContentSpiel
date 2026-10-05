require "test_helper"

class Admin::SettingsScreen::PublishingCardComponentTest < ViewComponent::TestCase
  def render_card(submitted: nil, errors: [])
    values = Admin::SettingsScreen::Values.new(site: SiteSetting.instance, submitted: submitted)
    render_inline Admin::SettingsScreen::PublishingCardComponent.new(values: values, errors: errors)
  end

  test "a sentence around a narrow number input, with the help under it" do
    render_card

    assert_selector "h2#publishing", text: "Publishing"
    assert_selector "section[aria-labelledby=publishing]"
    assert_text "Keep trashed items for"
    assert_text "days after an item is trashed."
    assert_selector "input[type=number][name='site_setting[trash_retention_days]'][min='0'][value='30'][aria-describedby='settings-trash_retention_days-help']"
    assert_selector "p#settings-trash_retention_days-help", text: "Set to 0 to keep trashed items until someone empties the trash."
  end

  test "shows what was typed after a refused save, and its error in the slot" do
    render_card(submitted: ActionController::Parameters.new(trash_retention_days: "-1").permit!, errors: [ "Trash retention days must be greater than or equal to 0" ])

    assert_selector "input[name='site_setting[trash_retention_days]'][value='-1']"
    assert_selector ".admin-column > #settings-trash_retention_days-errors p", text: /greater than or equal to 0/
  end
end
