require "test_helper"

class PublicSite::PathsTest < ActiveSupport::TestCase
  setup do
    @root = Page.create!(title: "Home", slug: "", published_at: 1.day.ago)
  end

  def current(record, locale = "en") = PublicSite::Paths.current_path(record, locale)

  test "root is / and children nest in every enabled locale" do
    about = Page.create!(parent: @root, title: "About", published_at: 1.day.ago)
    team = Page.create!(parent: about, title: "Team", published_at: 1.day.ago)

    assert_equal "/", current(@root)
    assert_equal "/about", current(about)
    assert_equal "/about/team", current(team, "de")
  end

  test "renaming keeps the old path as a redirect and cascades to descendants" do
    about = Page.create!(parent: @root, title: "About", published_at: 1.day.ago)
    team = Page.create!(parent: about, title: "Team", published_at: 1.day.ago)

    Mobility.with_locale(:en) { about.update!(slug: "company") }

    assert_equal "/company/team", current(team)
    old = PublicPath.find_by(locale: "en", path: "/about/team")
    assert_not old.current
    assert_equal team, old.record
  end

  test "a new page reclaims a path that is only a redirect" do
    about = Page.create!(parent: @root, title: "About", published_at: 1.day.ago)
    # Every enabled locale, not just :en: `about` was only ever titled in
    # English, so `LocalizedSlug` filled its other locales' slugs from that
    # same English title at creation -- renaming just :en here would leave
    # "about" still `about`'s *current* slug in :de/:es, and `fresh` below
    # would collide there instead of freely reclaiming "/about" in every
    # locale the way this test means to exercise.
    Locales.enabled.each { |locale| Mobility.with_locale(locale) { about.update!(slug: "company") } }

    fresh = Page.create!(parent: @root, title: "About", published_at: 1.day.ago)
    assert_equal "/about", current(fresh)
    assert_equal 1, PublicPath.where(locale: "en", path: "/about").count
  end

  test "a sibling cannot take a current path" do
    Page.create!(parent: @root, title: "About", published_at: 1.day.ago)
    clash = Page.new(parent: @root, title: "Other", slug: "about")
    assert_not clash.valid?
    assert clash.errors[Mobility.normalize_locale_accessor(:slug, :en)].any?
  end

  test "destroying a page removes its rows" do
    page = Page.create!(parent: @root, title: "Gone", published_at: 1.day.ago)
    page.destroy!
    assert_not PublicPath.exists?(record: page)
  end

  test "changes are announced after commit" do
    about = Page.create!(parent: @root, title: "About", published_at: 1.day.ago)
    events = []
    ActiveSupport::Notifications.subscribed(->(*, payload) { events << payload }, "public_paths.changed") do
      Mobility.with_locale(:en) { about.update!(slug: "company") }
    end
    assert_includes events, { record: about, locale: "en", from: "/about", to: "/company" }
  end

  test "rebuild! recreates current rows from slugs" do
    about = Page.create!(parent: @root, title: "About", published_at: 1.day.ago)
    PublicPath.delete_all
    PublicSite::Paths.rebuild!
    assert_equal "/about", current(about)
  end
end
