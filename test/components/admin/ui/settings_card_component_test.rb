require "test_helper"

class Admin::Ui::SettingsCardComponentTest < ViewComponent::TestCase
  def mail = SettingsSections.find("mail")

  test "the card is a section named by its heading, whose id is the caller's" do
    render_inline(Admin::Ui::SettingsCardComponent.new(heading_id: "mail", heading: "Mail", icon: :at_sign, family: :media, id: "settings-mail-card", data: { controller: "admin--settings--mail" })) { "<p data-body>The body</p>".html_safe }

    assert_selector "section#settings-mail-card.admin-settings-card[aria-labelledby=mail][data-controller='admin--settings--mail']", count: 1
    assert_selector "section#settings-mail-card > .admin-settings-card__head h2#mail", text: "Mail"
    assert_selector "section#settings-mail-card > .admin-settings-card__head + p[data-body]", text: "The body"
  end

  test "it carries no id of its own and appends a class" do
    render_inline(Admin::Ui::SettingsCardComponent.new(heading_id: "site", heading: "Site", icon: :pages, family: :structure, class: "extra")) { "Body" }

    assert_selector "section.admin-settings-card.extra[aria-labelledby=site]"
    assert_no_selector "section[id]"
  end

  test "it knows no Settings section: heading, icon and family are handed in" do
    render_inline(Admin::Ui::SettingsCardComponent.new(heading_id: "form-card-fields", heading: "Fields", icon: :clipboard_list, family: :form)) { "Body" }

    assert_selector "section[aria-labelledby=form-card-fields] h2#form-card-fields", text: "Fields"
    assert_selector ".admin-settings-card__head span[aria-hidden=true].bg-ic-form-bg svg"
  end

  test "the head carries the chip, the heading, the intro, then the head slots" do
    render_inline(Admin::Ui::SettingsCardComponent.new(heading_id: "mail", heading: "Mail", icon: :at_sign, family: :media, intro: "How mail is sent.")) do |card|
      card.with_head_end { "<span data-end>Tabs</span>".html_safe }
      card.with_head_note { "<p data-note>Working</p>".html_safe }
      card.with_heading_mark { "<i data-mark></i>".html_safe }
      "Body"
    end

    head = page.find(".admin-settings-card__head")
    chip = head.find("span[aria-hidden=true].size-5\\.5.bg-ic-media-bg", match: :first)
    assert chip.has_css?("svg")
    assert_selector ".admin-settings-card__head h2.text-h2.font-semibold.text-ink", text: "Mail"
    assert_selector ".admin-settings-card__head p.text-small.text-dim", text: "How mail is sent."
    assert_selector ".admin-settings-card__head h2 [data-mark]", count: 0
    html = head.native.to_html
    positions = [ "bg-ic-media-bg", "<h2", "data-mark", "How mail is sent.", "data-end", "data-note" ].map { |mark| html.index(mark) }
    assert positions.all?, "every part is in the head: #{positions.inspect}"
    assert_equal positions.sort, positions, "the chip, the heading, its mark, the intro, then head_end and head_note"
    assert_selector ".admin-settings-card__head > .admin-settings-card__end [data-end]"
    assert_selector ".admin-settings-card__head > .admin-settings-card__note [data-note]"
  end

  test "without an intro or slots the head is the chip and the heading alone" do
    render_inline(Admin::Ui::SettingsCardComponent.new(heading_id: "publishing", heading: "Publishing", icon: :file_text, family: :lists)) { "Body" }

    assert_selector ".admin-settings-card__head h2#publishing", text: "Publishing"
    assert_selector ".admin-settings-card__head .bg-ic-lists-bg"
    assert_no_selector ".admin-settings-card__head p"
    assert_equal 2, page.find(".admin-settings-card__head").all(:xpath, "./*").size
  end

  test "the card has no border of its own and its head is the rail's ground" do
    render_inline(Admin::Ui::SettingsCardComponent.new(heading_id: "mail", heading: "Mail", icon: :at_sign, family: :media)) { "Body" }

    card = page.find("section.admin-settings-card")
    assert_equal %w[admin-settings-card bg-surface rounded-card shadow-1], card[:class].split.sort & %w[admin-settings-card bg-surface rounded-card shadow-1]
    assert_no_match(/(?<![\w-])border(?:-|\s|\z)/, card[:class])
    head = page.find(".admin-settings-card__head")
    assert_includes head[:class].split, "bg-rail"
    assert_includes head[:class].split, "rounded-t-card"
    assert_no_match(/(?<![\w-])border(?:-|\s|\z)/, head[:class])
  end
end
