require "test_helper"

class Admin::SettingsScreen::GlanceComponentTest < ViewComponent::TestCase
  def render_glance(sections)
    site = SiteSetting.instance.reload
    render_inline Admin::SettingsScreen::GlanceComponent.new(sections: sections, site_setting: site, mail_settings: MailSettings.current(site, env: {}),
      images_progress: { total: 3, made: 3, failed: 0 }, locales: %w[en de es], default: "en")
  end

  test "the rows are only the sections handed in, in their order, under the heading, then the hint" do
    render_glance(SettingsSections::ALL)

    assert_selector "aside.admin-settings-glance[aria-labelledby=settings-glance-heading] > h2#settings-glance-heading", text: "At a glance"
    assert_equal %w[settings-glance-languages settings-glance-ai settings-glance-mail settings-glance-images],
      page.all("aside a").map { |link| link[:id] }, "the rows are the four with a state, in the nav's order; Site, Publishing and Forms have none"
    children = page.find("aside").native.element_children
    assert_equal "h2", children.first.name
    assert_equal "p", children.last.name
    assert_equal "Settings save together, with the bar at the foot: they are configuration, not content.", children.last.text.strip
    assert_includes children.last[:class].split, "text-small"
    assert_includes children.last[:class].split, "text-meta"

    render_glance(SettingsSections.for { |permission| permission == "languages.manage" })
    assert_equal %w[settings-glance-languages], page.all("aside a").map { |link| link[:id] }
  end

  test "with no section that has a state, there is no rail" do
    render_glance([ SettingsSections.find("site"), SettingsSections.find("publishing") ])

    assert_no_selector "aside"
  end
end
