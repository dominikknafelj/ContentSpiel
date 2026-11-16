require "test_helper"

class Admin::SettingsScreen::PostTypesCardComponentTest < ViewComponent::TestCase
  WORDS = "admin.components.settings_screen.post_types_card".freeze
  SWITCH = "input.cs-toggle[type=checkbox][role=switch][name='site_setting[content_types][]']".freeze

  def site_with(types)
    SiteSetting.instance.tap { |site| site.content_types = types }
  end

  def render_card(types: %w[blog resume_entry now_update], counts: {}, typed: nil, errors: [], changed: nil)
    site = site_with(types)
    values = Admin::SettingsScreen::Values.new(site: site_with(typed || types), submitted: (ActionController::Parameters.new(content_types: typed) if typed), stored: site)
    render_inline Admin::SettingsScreen::PostTypesCardComponent.new(section: SettingsSections.find("post_types"), site_setting: site,
      counts: counts, values: values, errors: errors)
  end

  test "a row per declared type: dot, label, description and the switch, ungrouped first, then the personal-site pair under its heading" do
    render_card

    assert_selector "section#settings-post_types-card h2#post_types", text: "Post types"
    assert_text I18n.t("#{WORDS}.intro")
    assert_equal %w[blog resume_entry now_update], page.all(SWITCH, visible: :all).map(&:value)
    assert_selector "[data-post-type=blog] .admin-type-dot", text: "Blog"
    assert_text I18n.t("admin.content_types.descriptions.blog")
    assert_equal [ "For a personal site" ], page.all("h3").map(&:text)
    order = page.all("[data-post-type], h3").map { |node| node.tag_name == "h3" ? "heading" : node["data-post-type"] }
    assert_equal %w[blog heading resume_entry now_update], order
    assert_selector "[data-post-type=blog] #{SWITCH}[checked]", visible: :all
  end

  test "a hidden empty value precedes the checkboxes" do
    render_card

    hidden = page.find("input[type=hidden][name='site_setting[content_types][]']", visible: :all)
    assert_equal "", hidden.value
    html = page.native.to_html
    assert_operator html.index(%(type="hidden" name="site_setting[content_types][]")), :<, html.index('class="cs-toggle')
  end

  test "the post count says 12 posts, 1 post, or nothing" do
    render_card(counts: { "blog" => 12, "resume_entry" => 1 })

    assert_selector "[data-post-type=blog] [data-post-count]", text: "12 posts"
    assert_selector "[data-post-type=resume_entry] [data-post-count]", text: "1 post"
    assert_no_selector "[data-post-type=now_update] [data-post-count]"
  end

  test "an undeclared stored name draws no row" do
    render_card(types: %w[blog events])

    assert_no_selector "[data-post-type=events]"
    assert_no_selector "#{SWITCH}[value=events]", visible: :all
  end

  test "a switched-on type with posts carries the line it says when unticked" do
    render_card(counts: { "blog" => 6 })

    row = page.find("[data-post-type=blog]", visible: :all)
    assert_equal "on", row["data-stored"]
    line = row.find("[data-leaving]", visible: :all)
    assert line[:hidden], "the line is hidden at rest"
    assert_equal "Its 6 posts leave the site when you save. They are kept, and come back when you switch it on again.", line.text(:all).strip
    assert_not_includes row.find(SWITCH, visible: :all)["aria-describedby"].to_s.split, line[:id], "a hidden line named by aria-describedby would be read at rest"
    assert_no_selector "[data-post-type=blog] [data-returning]", visible: :all
  end

  test "one post says the singular, in both lines" do
    render_card(types: %w[blog], counts: { "blog" => 1, "resume_entry" => 1 })

    assert_equal "Its 1 post leaves the site when you save. It is kept, and comes back when you switch it on again.",
      page.find("[data-post-type=blog] [data-leaving]", visible: :all).text(:all).strip
    assert_equal "Its 1 post comes back to the site when you save.",
      page.find("[data-post-type=resume_entry] [data-returning]", visible: :all).text(:all).strip
  end

  test "a switched-off type with posts carries the line it says when ticked" do
    render_card(types: %w[blog], counts: { "resume_entry" => 6 })

    row = page.find("[data-post-type=resume_entry]", visible: :all)
    assert_equal "off", row["data-stored"]
    line = row.find("[data-returning]", visible: :all)
    assert line[:hidden]
    assert_equal "Its 6 posts come back to the site when you save.", line.text(:all).strip
    assert_not_includes row.find(SWITCH, visible: :all)["aria-describedby"].to_s.split, line[:id], "a hidden line named by aria-describedby would be read at rest"
    assert_no_selector "[data-post-type=resume_entry] [data-leaving]", visible: :all
    assert_no_selector "[data-post-type=resume_entry] #{SWITCH}[checked]", visible: :all
  end

  test "a type with no posts draws neither line" do
    render_card(counts: { "blog" => 0 })

    assert_no_selector "[data-leaving], [data-returning]", visible: :all
  end

  test "the switch is a role=switch .cs-toggle named by the type's label and described by its description" do
    render_card

    switch = page.find("[data-post-type=blog] #{SWITCH}", visible: :all)
    assert_selector "label[for='#{switch[:id]}']", text: "Blog"
    description = page.find("[data-post-type=blog] [data-description]", visible: :all)
    assert_includes switch["aria-describedby"].split, description[:id]
  end

  test "what was typed beats what is stored, and a refused save names the field" do
    render_card(types: %w[blog resume_entry], typed: [ "" ], errors: [ "Keep at least one post type switched on." ], changed: "saved")

    assert_no_selector "#{SWITCH}[checked]", visible: :all
    assert_selector "[data-post-type=blog][data-stored=on]", visible: :all
    assert_selector "[data-field-name=content_types][data-save-bar-changed=saved]"
    assert_selector "[data-post-types-errors]", text: "Keep at least one post type switched on."
  end

  test "the two :has() rules that show a row's line exist in the stylesheet" do
    css = File.read(Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css"))

    assert_includes css, '[data-stored="on"]:has(.cs-toggle:not(:checked)) .admin-post-types__leaving'
    assert_includes css, '[data-stored="off"]:has(.cs-toggle:checked) .admin-post-types__returning'
  end
end
