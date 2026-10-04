require "test_helper"

class Locales::MakeDefaultTest < ActiveSupport::TestCase
  setup { with_locales(%w[en de es], default: "en") }

  test "makes an enabled language the default, carries the title and records the event" do
    page = as_owner { create_page(title: "About", translations: { "de" => { title: "Über" } }) }
    Current.site.update_columns(title: { "en" => "Test Site" }, tagline: { "en" => "Tagline" })

    result = as_owner { Locales::MakeDefault.call("de") }

    assert result.ok?, result.errors.inspect
    site = Current.site.reload
    assert_equal "de", site.default_locale
    assert_equal "Test Site", site.title(locale: "de"), "the title is carried into the new default"
    assert_equal "Tagline", site.tagline(locale: "de")
    event = Audit::Event.find_by!(action: "language.default_changed")
    assert_equal [ "en", "de" ], event.field_changes["default_locale"]
    assert_equal "de", event.metadata["code"]
    assert_equal site, event.subject
    assert_equal %w[en es], Translations::State.where(record_type: "Page", record_id: page.id).pluck(:locale).sort, "the states were rebuilt for the new default"
  end

  def state_of(record, locale) = Translations::State.find_by(record_type: record.class.polymorphic_name, record_id: record.id, locale: locale)&.state

  test "rebuilds the translation states synchronously" do
    page = as_owner { create_page(title: "About", translations: { "de" => { title: "Über" } }) }
    assert_equal "complete", state_of(page, "de")
    assert_equal "missing", state_of(page, "es")

    assert as_owner { Locales::MakeDefault.call("de") }.ok?

    # Now "de" is the original: it is no longer a target, and "en" is one.
    assert_nil state_of(page, "de")
    assert_equal "complete", state_of(page, "en")
  end

  test "a language that isn't enabled is refused" do
    result = as_owner { Locales::MakeDefault.call("fr") }

    assert_not result.ok?
    assert_equal "en", Current.site.reload.default_locale
    assert_not Audit::Event.exists?(action: "language.default_changed")
  end

  test "the language already being the default is a no-op" do
    result = as_owner { Locales::MakeDefault.call("en") }

    assert result.ok?
    assert_not Audit::Event.exists?(action: "language.default_changed")
  end

  test "needs languages.manage, not settings.manage" do
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "settings.manage", scope: {})

    result = as(users(:editor_branch)) { Locales::MakeDefault.call("de") }

    assert result.denied?
    assert_equal "en", Current.site.reload.default_locale
    assert_equal 1, Audit::Event.where(action: "access.denied").count

    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "languages.manage", scope: {})
    assert as(users(:editor_branch)) { Locales::MakeDefault.call("de") }.ok?
    assert_equal "de", Current.site.reload.default_locale
  end

  test "a supported but disabled language is refused, and nothing stays assigned on the shared site" do
    Current.site.update_columns(locales: [ { "code" => "en" }, { "code" => "de" } ])
    site = Current.site.reload

    result = as_owner { Locales::MakeDefault.call("es") }

    assert_not result.ok?
    assert_equal [ "es isn't an enabled language" ], result.errors
    assert_equal "en", site.default_locale
    assert_not site.changed?
  end

  test "a blank code asks for an enabled language" do
    result = as_owner { Locales::MakeDefault.call("") }

    assert_equal [ "Choose an enabled language" ], result.errors
  end

  test "a failed save restores the default and the carried title on the shared site" do
    Current.site.update_columns(title: { "en" => "Test Site" })
    site = Current.site.reload
    # A row invalid for an unrelated reason makes the save fail after the
    # model has already carried the title across.
    site.update_columns(locales: [ { "code" => "en", "fallbacks" => [ "fr" ] }, { "code" => "de" } ])

    result = as_owner { Locales::MakeDefault.call("de") }

    assert_not result.ok?
    assert_equal "en", site.default_locale
    assert_nil site.read_attribute(:title)["de"]
    assert_not site.changed?, site.changes.inspect
  end
end
