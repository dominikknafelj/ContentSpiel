require "test_helper"

class Admin::SettingsScreen::SectionCardTest < ViewComponent::TestCase
  def mail = SettingsSections.find("mail")

  test "a section's options are its id, its name read by the key, its icon and its family" do
    view = Object.new.tap { |reader| reader.define_singleton_method(:t) { |key| I18n.t(key) } }
    options = Admin::SettingsScreen::SectionCard.options(mail, view)

    assert_equal({ heading_id: "mail", heading: "Mail", icon: mail.icon, family: mail.family }, options)
    assert_equal "admin.components.settings_screen.sections.mail", Admin::SettingsScreen::SectionCard.word_key(mail)
  end
end
