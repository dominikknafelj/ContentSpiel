require "test_helper"

class Settings::SaveTest < ActiveSupport::TestCase
  test "saves the settings and records settings.updated with what changed" do
    result = as_owner { Settings::Save.call(Current.site, attributes: { title: "New title", social_link_rows: [ { name: "Mastodon", url: "https://example.social/@me" } ] }) }

    assert result.ok?, result.errors.inspect
    assert_equal "New title", Current.site.reload.title
    event = Audit::Event.find_by!(action: "settings.updated")
    assert_equal Current.site, event.subject
    # Translated (translation helpers spec §5), so listed per language.
    assert_equal "New title", event.field_changes["en title"].last
  end

  test "a save that changes nothing records nothing" do
    as_owner { Settings::Save.call(Current.site, attributes: { title: Current.site.title }) }

    assert_not Audit::Event.exists?(action: "settings.updated")
  end

  test "an invalid save fails without an event" do
    result = as_owner { Settings::Save.call(Current.site, attributes: { default_locale: "xx" }) }

    assert_not result.ok?
    assert_not Audit::Event.exists?(action: "settings.updated")
  end

  test "needs settings.manage" do
    result = as(users(:author)) { Settings::Save.call(Current.site, attributes: { title: "Nope" }) }

    assert_equal [ "You don't have permission to manage settings" ], result.errors
    assert_not_equal "Nope", Current.site.reload.title
  end

  test "changing the enabled languages also needs languages.manage" do
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "settings.manage", scope: {})

    result = as(users(:editor_branch)) { Settings::Save.call(Current.site, attributes: { locales: [ { "code" => "en" } ] }) }
    assert_equal [ "You don't have permission to manage languages" ], result.errors

    result = as(users(:editor_branch)) { Settings::Save.call(Current.site, attributes: { tagline: "Fine" }) }
    assert result.ok?, result.errors.inspect
  end

  test "the title and tagline are saved per language through translations" do
    with_locales(%w[en de], default: "en")

    result = as_owner do
      Settings::Save.call(Current.site, translations: { "de" => { title: "Danas Notizen", tagline: "Was ich gelernt habe", logo: nil } })
    end

    assert result.ok?, result.errors.inspect
    site = Current.site.reload
    assert_equal "Test Site", site.title(locale: "en")
    assert_equal "Danas Notizen", site.title(locale: "de")
    assert_equal "Was ich gelernt habe", site.tagline(locale: "de")
    event = Audit::Event.find_by!(action: "settings.updated")
    assert_equal [ nil, "Danas Notizen" ], event.field_changes["de title"]
  end

  test "a blank title in the default language is refused" do
    result = as_owner { Settings::Save.call(Current.site, translations: { "en" => { title: " " } }) }

    assert_not result.ok?
    assert_equal "Test Site", Current.site.reload.title(locale: "en")
  end
end
