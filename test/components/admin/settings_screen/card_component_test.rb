require "test_helper"

class Admin::SettingsScreen::CardComponentTest < ViewComponent::TestCase
  def mail = SettingsSections.find("mail")

  test "the card is a section named by its heading, whose id is the section's anchor" do
    render_inline(Admin::SettingsScreen::CardComponent.new(section: mail, data: { controller: "admin--settings--mail" })) { "<p data-body>The body</p>".html_safe }

    assert_selector "section#settings-mail-card.admin-settings-card[aria-labelledby=mail][data-controller='admin--settings--mail']", count: 1
    assert_selector "section#settings-mail-card > .admin-settings-card__head h2#mail", text: "Mail"
    assert_selector "section#settings-mail-card > .admin-settings-card__head + p[data-body]", text: "The body"
  end

  test "an id the card is handed is the one it carries" do
    render_inline(Admin::SettingsScreen::CardComponent.new(section: SettingsSections.find("site"), id: "site-elsewhere", class: "extra")) { "Body" }

    assert_selector "section#site-elsewhere.admin-settings-card.extra[aria-labelledby=site]"
  end

  test "the head carries the section's chip, its word, its intro, then the head slots" do
    render_inline(Admin::SettingsScreen::CardComponent.new(section: mail, intro: "How mail is sent.")) do |card|
      card.with_head_end { "<span data-end>Tabs</span>".html_safe }
      card.with_head_note { "<p data-note>Working</p>".html_safe }
      "Body"
    end

    head = page.find(".admin-settings-card__head")
    chip = head.find("span[aria-hidden=true].size-5\\.5.bg-ic-media-bg", match: :first)
    assert chip.has_css?("svg")
    assert_selector ".admin-settings-card__head h2.text-h2.font-semibold.text-ink", text: "Mail"
    assert_selector ".admin-settings-card__head p.text-small.text-dim", text: "How mail is sent."
    html = head.native.to_html
    positions = [ "bg-ic-media-bg", "<h2", "How mail is sent.", "data-end", "data-note" ].map { |mark| html.index(mark) }
    assert positions.all?, "every part is in the head: #{positions.inspect}"
    assert_equal positions.sort, positions, "the chip, the word, the intro, then head_end and head_note"
  end

  test "without an intro or slots the head is the chip and the word alone" do
    render_inline(Admin::SettingsScreen::CardComponent.new(section: SettingsSections.find("publishing"))) { "Body" }

    assert_selector ".admin-settings-card__head h2#publishing", text: "Publishing"
    assert_selector ".admin-settings-card__head .bg-ic-lists-bg"
    assert_no_selector ".admin-settings-card__head p"
    assert_equal 2, page.find(".admin-settings-card__head").all(:xpath, "./*").size
  end

  test "the card has no border of its own and its head is the rail's ground" do
    render_inline(Admin::SettingsScreen::CardComponent.new(section: mail)) { "Body" }

    card = page.find("section.admin-settings-card")
    assert_equal %w[admin-settings-card bg-surface rounded-card shadow-1], card[:class].split.sort & %w[admin-settings-card bg-surface rounded-card shadow-1]
    assert_no_match(/(?<![\w-])border(?:-|\s|\z)/, card[:class])
    head = page.find(".admin-settings-card__head")
    assert_includes head[:class].split, "bg-rail"
    assert_includes head[:class].split, "rounded-t-card"
    assert_no_match(/(?<![\w-])border(?:-|\s|\z)/, head[:class])
  end

  test "the section's word is its key" do
    I18n.backend.store_translations(:en, admin: { components: { settings_screen: { sections: { mail: "Post" } } } })
    render_inline(Admin::SettingsScreen::CardComponent.new(section: mail)) { "Body" }

    assert_selector "h2#mail", text: "Post"
  ensure
    I18n.backend.store_translations(:en, admin: { components: { settings_screen: { sections: { mail: "Mail" } } } })
  end
end
