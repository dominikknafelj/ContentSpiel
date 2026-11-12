require "test_helper"

class SettingsSectionsTest < ActiveSupport::TestCase
  test "the eight sections in the nav's order, each with its right, family, icon and whether it is an owner's" do
    rows = SettingsSections::ALL.map { |section| [ section.id, section.permission, section.family, section.icon, section.owner_only ] }

    assert_equal [
      [ "site", "settings.manage", :structure, :pages, false ],
      [ "languages", "languages.manage", :text, :translations, false ],
      [ "publishing", "settings.manage", :lists, :file_text, false ],
      [ "forms", "settings.manage", :form, :clipboard_list, false ],
      [ "ai", "settings.manage", :code, :assistant, false ],
      [ "mail", "settings.manage", :media, :at_sign, false ],
      [ "sign_in", "settings.manage", :neutral, :fingerprint, true ],
      [ "images", "settings.manage", :media, :image, false ]
    ], rows
    assert_equal %w[site languages publishing forms ai mail sign_in images], SettingsSections.ids
    assert SettingsSections::ALL.frozen?
  end

  test "for keeps the sections whose right is held, and find raises on an unknown id" do
    only_settings = SettingsSections.for { |permission| permission == "settings.manage" }
    only_languages = SettingsSections.for { |permission| permission == "languages.manage" }

    assert_equal %w[site publishing forms ai mail images], only_settings.map(&:id)
    assert_equal %w[languages], only_languages.map(&:id)
    assert_empty SettingsSections.for { false }
    assert_empty SettingsSections.for(owner: true) { false }, "an owner-only section still needs its right"

    assert_equal :at_sign, SettingsSections.find("mail").icon
    assert_equal "mail", SettingsSections.find(:mail).id
    error = assert_raises(KeyError) { SettingsSections.find("billing") }
    assert_match "billing", error.message
  end

  test "the sign-in section is offered to an owner only, in the nav, the cards and ⌘K" do
    assert_equal %w[site publishing forms ai mail sign_in images], SettingsSections.for(owner: true) { |permission| permission == "settings.manage" }.map(&:id)
    assert_not_includes SettingsSections.for(owner: false) { true }.map(&:id), "sign_in"

    owner = users(:one)
    admin = users(:two)
    assert AccessControl.holds?(admin, "settings.manage", channel: :admin), "the premise: the admin may manage settings"
    jump = ->(actor) { Jump::Search.new(actor: actor, query: "", modules: []).groups.find { |group| group[:label] == "Settings" }[:rows].map { |row| row[:route].last[:anchor] } }
    assert_includes jump.call(owner), "sign_in"
    assert_not_includes jump.call(admin), "sign_in"
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
