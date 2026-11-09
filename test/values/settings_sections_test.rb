require "test_helper"

class SettingsSectionsTest < ActiveSupport::TestCase
  test "the seven sections in the nav's order, each with its right, family and icon" do
    rows = SettingsSections::ALL.map { |section| [ section.id, section.permission, section.family, section.icon ] }

    assert_equal [
      [ "site", "settings.manage", :structure, :pages ],
      [ "languages", "languages.manage", :text, :translations ],
      [ "publishing", "settings.manage", :lists, :file_text ],
      [ "forms", "settings.manage", :form, :clipboard_list ],
      [ "ai", "settings.manage", :code, :assistant ],
      [ "mail", "settings.manage", :media, :at_sign ],
      [ "images", "settings.manage", :media, :image ]
    ], rows
    assert_equal %w[site languages publishing forms ai mail images], SettingsSections.ids
    assert SettingsSections::ALL.frozen?
  end

  test "for keeps the sections whose right is held, and find raises on an unknown id" do
    only_settings = SettingsSections.for { |permission| permission == "settings.manage" }
    only_languages = SettingsSections.for { |permission| permission == "languages.manage" }

    assert_equal %w[site publishing forms ai mail images], only_settings.map(&:id)
    assert_equal %w[languages], only_languages.map(&:id)
    assert_empty SettingsSections.for { false }

    assert_equal :at_sign, SettingsSections.find("mail").icon
    assert_equal "mail", SettingsSections.find(:mail).id
    error = assert_raises(KeyError) { SettingsSections.find("billing") }
    assert_match "billing", error.message
  end

  test "each family is an icon chip's and each icon is drawn by the icon partial" do
    SettingsSections::ALL.each do |section|
      assert Admin::Ui::IconChipComponent::FAMILIES.key?(section.family), "#{section.id}: #{section.family.inspect} is no icon chip family"
      assert_not_equal :accent, section.family
      svg = ApplicationController.render(partial: "admin/shared/icon", locals: { name: section.icon })
      assert_match "<svg", svg, "#{section.id}: #{section.icon.inspect} is not drawn by the icon partial"
    end
  end
end
