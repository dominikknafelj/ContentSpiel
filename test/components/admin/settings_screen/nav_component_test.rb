require "test_helper"

class Admin::SettingsScreen::NavComponentTest < ViewComponent::TestCase
  test "one anchor per section, in the screen's order" do
    render_inline Admin::SettingsScreen::NavComponent.new(sections: Admin::SettingsScreen::NavComponent::SECTIONS)

    assert_selector "nav[aria-label='Settings sections'] a", count: 4
    assert_equal %w[#site #languages #publishing #ai], page.all("a").map { |a| a[:href] }
    assert_equal [ "Site", "Languages", "Publishing", "AI translation" ], page.all("a").map(&:text)
  end

  # Same-page links: a `_top` link would be a Turbo visit, which the save
  # footer's leave guard asks about.
  test "the links are plain fragment links, never visits" do
    render_inline Admin::SettingsScreen::NavComponent.new(sections: Admin::SettingsScreen::NavComponent::SECTIONS)

    assert_no_selector "a[data-turbo-frame]"
  end

  test "sections_for keeps the sections whose right the viewer holds" do
    only_settings = Admin::SettingsScreen::NavComponent.sections_for { |permission| permission == "settings.manage" }
    only_languages = Admin::SettingsScreen::NavComponent.sections_for { |permission| permission == "languages.manage" }

    assert_equal %w[site publishing ai], only_settings.map { |section| section[:id] }
    assert_equal %w[languages], only_languages.map { |section| section[:id] }
    assert_empty Admin::SettingsScreen::NavComponent.sections_for { false }
  end

  test "renders nothing without sections" do
    render_inline Admin::SettingsScreen::NavComponent.new(sections: [])

    assert_no_selector "nav"
  end
end
