require "test_helper"

class Admin::DashboardScreen::TranslationCardComponentTest < ViewComponent::TestCase
  setup do
    Current.actor = users(:one)
    Current.channel = :admin
    with_locales(%w[en de es], default: "en")
  end
  teardown { Current.reset }

  def entries = Dashboard::TranslationNeeds.new(actor: users(:one)).entries

  test "its numbers equal StateIndex.summary and each language is named in its own language" do
    create_post(title: "One")
    create_page(title: "Two")
    summary = Translations::StateIndex.summary("de", [ Page.kept, Post.kept ])
    assert_operator summary[:missing], :>, 0

    render_inline Admin::DashboardScreen::TranslationCardComponent.new(entries:)

    entry = entries.find { |e| e.locale == "de" }
    assert_equal summary.slice(:total, :complete, :missing, :outdated), entry.to_h.slice(:total, :complete, :missing, :outdated)
    assert_selector "[data-locale=de]", text: /Deutsch.*#{summary[:missing]} missing/m
    assert_selector "[data-locale=es]", text: /Español/
    assert_selector "[data-locale=de] [role=progressbar][aria-valuenow='#{(summary[:complete] * 100.0 / summary[:total]).round}']"
  end

  # Task 16's d2: the shared card caps its rows at five; a language is a row,
  # so a sixth and seventh must not disappear.
  test "every language gets its row, however many there are" do
    fake = %w[aa bb cc dd ee ff gg].map do |code|
      Dashboard::TranslationNeeds::Entry.new(locale: code, name: code.upcase, total: 4, complete: 2, missing: 1, outdated: 1, item: nil)
    end
    render_inline Admin::DashboardScreen::TranslationCardComponent.new(entries: fake)
    assert_selector "[data-locale]", count: 7
  end

  test "an outdated item is offered as a link to its editor in that language" do
    post = create_post(title: "Changing")
    Translations::State.where(record_type: "Post", record_id: post.id, locale: "de").update_all(state: "outdated", outdated_count: 1, missing_count: 0)

    render_inline Admin::DashboardScreen::TranslationCardComponent.new(entries:)

    assert_selector "[data-locale=de] a[href='/cs-studio/posts/#{post.id}?locale=de']", text: "Changing"
    assert_text "1 outdated"
  end

  test "hidden with one language, and with nothing readable" do
    with_locales(%w[en], default: "en")
    render_inline Admin::DashboardScreen::TranslationCardComponent.new(entries:)
    assert_no_selector "section"

    with_locales(%w[en de], default: "en")
    assert_empty Dashboard::TranslationNeeds.new(actor: users(:editor_branch)).entries
  end

  test "the language name is plain text when the viewer can't open the overview" do
    group = AccessControl::Group.create!(name: "Uploaders")
    group.grants.create!(permission: "media.upload", scope: {})
    user = User.create!(email_address: "uploader@example.com", password: "password12345")
    AccessControl::Membership.create!(user:, group:)
    Current.actor = user
    render_inline Admin::DashboardScreen::TranslationCardComponent.new(entries: Dashboard::TranslationNeeds.new(actor: user).entries)

    assert_selector "[data-locale=de]", text: "Deutsch"
    assert_no_selector "a"
  end
end
