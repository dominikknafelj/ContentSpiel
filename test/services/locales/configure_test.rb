require "test_helper"

class Locales::ConfigureTest < ActiveSupport::TestCase
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
end
