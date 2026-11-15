require "test_helper"

class Locales::ConfigureTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    # The fixture's own default (`site_settings.yml`) leaves `locales` at the
    # schema default -- en, de, es, in that order, none with fallbacks.
    @site = site_settings(:default)
  end

  test "reorders the enabled languages" do
    result = Locales::Configure.call([ { code: "es" }, { code: "en" }, { code: "de" } ], actor: nil)

    assert result.ok?, result.errors.to_sentence
    assert_equal %w[es en de], @site.reload.locale_codes
  end

  test "sets fallbacks for a language" do
    result = Locales::Configure.call([ { code: "en" }, { code: "de", fallbacks: [ "en" ] }, { code: "es" } ], actor: nil)

    assert result.ok?, result.errors.to_sentence
    assert_equal [ "en" ], @site.reload.locale_entry("de")["fallbacks"]
  end

  test "reordering changes the fallback chain's final tier" do
    Locales::Configure.call([ { code: "es" }, { code: "en" }, { code: "de" } ], actor: nil)

    # "de" has no configured fallbacks and isn't the default ("en"), so its
    # own chain is [de, en (default), then every other enabled language in
    # the order Configure just wrote] -- "es" now sorts ahead of "en" is
    # impossible (default always comes right after the locale itself), but
    # ahead of where "es" used to sit in the unordered default.
    assert_equal %w[de en es], Locales.fallback_chain("de")
  end

  test "fails when a fallback points to a language that isn't enabled" do
    result = Locales::Configure.call([ { code: "en" }, { code: "de", fallbacks: [ "fr" ] }, { code: "es" } ], actor: nil)

    assert_not result.ok?
    assert_equal %w[en de es], @site.reload.locale_codes
  end

  test "fails when the entries don't match the currently enabled languages" do
    result = Locales::Configure.call([ { code: "en" }, { code: "de" } ], actor: nil)

    assert_not result.ok?
    assert_includes result.errors.join, "exactly the enabled languages"
    assert_equal %w[en de es], @site.reload.locale_codes
  end

  test "a stale order is refused when another change enabled a language meanwhile" do
    stale = SiteSetting.find(@site.id)
    SiteSetting.find(@site.id).update!(locales: stale.locales + [ { "code" => "fr" } ])

    Current.site = stale
    result = Locales::Configure.call([ { code: "es" }, { code: "en" }, { code: "de" } ], actor: nil)

    assert_not result.ok?
    assert_includes result.errors.join, "exactly the enabled languages"
    assert_equal %w[en de es fr], SiteSetting.find(@site.id).locale_codes
  end

  test "a change of languages enqueues the search index's rebuild after the commit" do
    clear_enqueued_jobs
    SiteSetting.transaction do
      assert Locales::Configure.call([ { code: "en" }, { code: "de", fallbacks: [ "es" ] }, { code: "es" } ], actor: nil).ok?
      assert_no_enqueued_jobs only: SiteSearch::ReindexJob
    end
    assert_enqueued_with(job: SiteSearch::ReindexJob, args: [ "postgres" ])

    clear_enqueued_jobs
    assert Locales::Configure.call([ { code: "en" }, { code: "de", fallbacks: [ "es" ] }, { code: "es" } ], actor: nil).ok?
    # The default and de's own fallback come before the order's tier in
    # every chain, so putting de first moves none.
    assert Locales::Configure.call([ { code: "de", fallbacks: [ "es" ] }, { code: "en" }, { code: "es" } ], actor: nil).ok?
    assert_equal %w[de en es], Current.site.reload.locale_codes
    # A configure that moves no chain enqueues none.
    assert_no_enqueued_jobs(only: SiteSearch::ReindexJob)
  end
end
