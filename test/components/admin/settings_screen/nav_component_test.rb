require "test_helper"

class Admin::SettingsScreen::NavComponentTest < ViewComponent::TestCase
  test "one anchor per section, in the screen's order" do
    render_inline Admin::SettingsScreen::NavComponent.new(sections: SettingsSections::ALL)

    assert_selector "nav[aria-label='Settings sections'] a", count: 8
    assert_equal %w[#site #languages #publishing #forms #ai #mail #sign_in #images], page.all("a").map { |a| a[:href] }
    assert_equal [ "Site", "Languages", "Publishing", "Forms", "AI translation", "Mail", "Sign-in", "Images" ], page.all("a").map(&:text)
  end

  # Same-page links: a `_top` link would be a Turbo visit, which the save
  # footer's leave guard asks about.
  test "the links are plain fragment links, never visits" do
    render_inline Admin::SettingsScreen::NavComponent.new(sections: SettingsSections::ALL)

    assert_no_selector "a[data-turbo-frame]"
  end

  test "the nav is the current-section controller's, and the server marks no link current" do
    render_inline Admin::SettingsScreen::NavComponent.new(sections: SettingsSections::ALL)

    assert_selector "nav[aria-label='Settings sections'][data-controller='admin--settings--nav'][data-action~='turbo:before-cache@document->admin--settings--nav#reset']"
    assert_selector "a[data-admin--settings--nav-target=link]", count: 8
    assert_no_selector "a[aria-current]"
  end

  test "each link carries its section's chip before its word" do
    render_inline Admin::SettingsScreen::NavComponent.new(sections: SettingsSections::ALL)

    links = page.all("nav a")
    assert_equal 8, links.size
    SettingsSections::ALL.zip(links).each do |section, link|
      chip = link.native.element_children.first
      assert_equal [ "span", "true" ], [ chip.name, chip["aria-hidden"] ], section.id
      assert_includes chip[:class].split, "size-5.5", section.id
      assert_includes chip[:class].split, Admin::Ui::IconChipComponent::FAMILIES.fetch(section.family).split.first, section.id
      assert chip.at_css("svg"), section.id
    end
    assert_equal "Languages", links[1].text
  end

  test "its words are keys" do
    assert_equal "Settings sections", I18n.t("admin.components.settings_screen.nav.label")
    I18n.backend.store_translations(:en, admin: { components: { settings_screen: { nav: { label: "Parts of Settings" }, sections: { ai: "Machine translation" } } } })
    render_inline Admin::SettingsScreen::NavComponent.new(sections: SettingsSections::ALL)

    assert_selector "nav[aria-label='Parts of Settings'] a[href='#ai']", text: "Machine translation"
  ensure
    I18n.backend.store_translations(:en, admin: { components: { settings_screen: { nav: { label: "Settings sections" }, sections: { ai: "AI translation" } } } })
  end

  test "renders nothing without sections" do
    render_inline Admin::SettingsScreen::NavComponent.new(sections: [])

    assert_no_selector "nav"
  end
end
