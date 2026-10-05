require "test_helper"

class Settings::SaveTest < ActiveSupport::TestCase
  test "saves the settings and records settings.updated with what changed" do
    result = as_owner { Settings::Save.call(Current.site, attributes: { social_link_rows: [ { name: "Mastodon", url: "https://example.social/@me" } ] }, translations: { "en" => { title: "New title" } }) }

    assert result.ok?, result.errors.inspect
    assert_equal "New title", Current.site.reload.title
    event = Audit::Event.find_by!(action: "settings.updated")
    assert_equal Current.site, event.subject
    # Translated (translation helpers spec §5), so listed per language.
    assert_equal "New title", event.field_changes["en title"].last
  end

  test "a save that changes nothing records nothing" do
    as_owner { Settings::Save.call(Current.site, translations: { "en" => { title: Current.site.title(locale: "en") } }) }

    assert_not Audit::Event.exists?(action: "settings.updated")
  end

  test "an invalid save fails without an event" do
    result = as_owner { Settings::Save.call(Current.site, attributes: { default_locale: "xx" }) }

    assert_not result.ok?
    assert_not Audit::Event.exists?(action: "settings.updated")
  end

  test "needs settings.manage" do
    result = as(users(:author)) { Settings::Save.call(Current.site, translations: { "en" => { title: "Nope" } }) }

    assert_equal [ "You don't have permission to manage settings" ], result.errors
    assert_not_equal "Nope", Current.site.reload.title
  end

  test "changing the enabled languages also needs languages.manage" do
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "settings.manage", scope: {})

    result = as(users(:editor_branch)) { Settings::Save.call(Current.site, attributes: { locales: [ { "code" => "en" } ] }) }
    assert_equal [ "You don't have permission to manage languages" ], result.errors

    result = as(users(:editor_branch)) { Settings::Save.call(Current.site, translations: { "en" => { tagline: "Fine" } }) }
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

  # The title and tagline are per language: through `attributes:` they'd be
  # written in whatever `Mobility.locale` is ambient, so they're refused
  # there outright rather than silently landing in the wrong language.
  test "the title or tagline passed as plain attributes is refused" do
    assert_raises(ArgumentError) { Settings::Save.new(Current.site, attributes: { title: "Ambient" }) }
    assert_raises(ArgumentError) { Settings::Save.new(Current.site, attributes: { "tagline" => "Ambient" }) }
    assert_equal "Test Site", Current.site.reload.title(locale: "en")
  end

  # --- languages: (decision D5) ---

  def reorder(*codes) = codes.map { |code| { "code" => code } }

  def grant_to_branch_editors(*keys)
    keys.each { |key| AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: key, scope: {}) }
  end

  test "languages: reorders and sets fallbacks, recording language.configured" do
    result = as_owner do
      Settings::Save.call(Current.site, languages: [ { "code" => "es" }, { "code" => "en" }, { "code" => "de", "fallbacks" => [ "en" ] } ])
    end

    assert result.ok?, result.errors.inspect
    site = Current.site.reload
    assert_equal %w[es en de], site.locale_codes
    assert_equal [ "en" ], site.locale_entry("de")["fallbacks"]
    assert Audit::Event.exists?(action: "language.configured")
    assert_not Audit::Event.exists?(action: "settings.updated")
  end

  test "languages: that change nothing record nothing" do
    as_owner { Settings::Save.call(Current.site, languages: reorder("en", "de", "es")) }

    assert_not Audit::Event.exists?(action: "language.configured")
  end

  test "site fields and languages in one call write both and record both events" do
    result = as_owner do
      Settings::Save.call(Current.site, attributes: { time_zone: "Europe/Berlin" }, translations: { "en" => { tagline: "Hi" } },
        languages: reorder("de", "en", "es"))
    end

    assert result.ok?, result.errors.inspect
    site = Current.site.reload
    assert_equal %w[de en es], site.locale_codes
    assert_equal "Hi", site.tagline(locale: "en")
    settings_event = Audit::Event.find_by!(action: "settings.updated")
    assert_equal "Hi", settings_event.field_changes["en tagline"].last
    assert_not settings_event.field_changes.key?("locales"), "the language order belongs to language.configured"
    assert Audit::Event.exists?(action: "language.configured")
  end

  test "languages-only needs only languages.manage" do
    grant_to_branch_editors("languages.manage")

    result = as(users(:editor_branch)) { Settings::Save.call(Current.site, languages: reorder("de", "en", "es")) }

    assert result.ok?, result.errors.inspect
    assert_equal %w[de en es], Current.site.reload.locale_codes
  end

  test "an actor with only languages.manage is refused the whole call: nothing written, one access.denied" do
    grant_to_branch_editors("languages.manage")

    result = as(users(:editor_branch)) do
      Settings::Save.call(Current.site, attributes: { time_zone: "Europe/Berlin" }, languages: reorder("de", "en", "es"))
    end

    assert result.denied?
    site = Current.site.reload
    assert_equal %w[en de es], site.locale_codes
    assert_not_equal "Europe/Berlin", site.time_zone
    assert_equal 1, Audit::Event.where(action: "access.denied").count
    assert_equal "settings.manage", Audit::Event.find_by!(action: "access.denied").metadata["permission"]
    assert_not Audit::Event.exists?(action: "language.configured")
  end

  test "an actor with only settings.manage is refused the whole call: nothing written, one access.denied" do
    grant_to_branch_editors("settings.manage")

    result = as(users(:editor_branch)) do
      Settings::Save.call(Current.site, attributes: { time_zone: "Europe/Berlin" }, languages: reorder("de", "en", "es"))
    end

    assert result.denied?
    site = Current.site.reload
    assert_equal %w[en de es], site.locale_codes
    assert_not_equal "Europe/Berlin", site.time_zone
    assert_equal 1, Audit::Event.where(action: "access.denied").count
    assert_equal "languages.manage", Audit::Event.find_by!(action: "access.denied").metadata["permission"]
    assert_not Audit::Event.exists?(action: "settings.updated")
  end

  test "an actor with neither right is denied once, for settings.manage (checked first)" do
    result = as(users(:editor_branch)) do
      Settings::Save.call(Current.site, translations: { "en" => { tagline: "x" } }, languages: reorder("de", "en", "es"))
    end

    assert result.denied?
    assert_equal 1, Audit::Event.where(action: "access.denied").count
    assert_equal "settings.manage", Audit::Event.find_by!(action: "access.denied").metadata["permission"]
  end

  test "an invalid site field rolls the language order back" do
    result = as_owner do
      Settings::Save.call(Current.site, attributes: { time_zone: "Not/AZone" }, languages: reorder("de", "en", "es"))
    end

    assert_not result.ok?
    assert_equal %w[en de es], Current.site.reload.locale_codes
    assert_not Audit::Event.exists?(action: "language.configured")
  end

  test "an invalid language list rolls the site fields back and records no event" do
    result = as_owner do
      Settings::Save.call(Current.site, translations: { "en" => { tagline: "Rolled back" } }, languages: reorder("en", "de"))
    end

    assert_not result.ok?
    assert_equal [ "must list exactly the enabled languages" ], result.errors
    # The object itself, before any reload (final fix wave, S-M2): it is
    # `Current.site`, read by everything rendered after the refusal.
    assert_nil Current.site.tagline(locale: "en")
    assert_equal %w[en de es], Current.site.locale_codes
    assert_not Current.site.changed?
    assert_nil Current.site.reload.tagline(locale: "en")
    assert_not Audit::Event.exists?(action: "settings.updated")
    assert_not Audit::Event.exists?(action: "language.configured")
  end

  # --- the AI key's date (decision D11) ---

  test "saving a key stamps its date, removing it clears it, an unrelated save leaves it" do
    as_owner { assert Settings::Save.call(Current.site, attributes: { ai_api_key: "sk-test-1" }).ok? }
    site = Current.site.reload
    assert site.ai_api_key_set?
    assert_in_delta Time.current, site.ai_api_key_saved_at, 5.seconds
    assert_equal site.ai_api_key_saved_at.in_time_zone(site.effective_time_zone).to_date, site.ai_api_key_saved_on

    stamped = site.ai_api_key_saved_at
    as_owner { assert Settings::Save.call(Current.site, translations: { "en" => { tagline: "Other" } }).ok? }
    assert_equal stamped, Current.site.reload.ai_api_key_saved_at

    as_owner { assert Settings::Save.call(Current.site, attributes: { ai_api_key: nil }).ok? }
    site = Current.site.reload
    assert_not site.ai_api_key_set?
    assert_nil site.ai_api_key_saved_at
    assert_nil site.ai_api_key_saved_on
  end

  test "a key stored before the column existed has no date" do
    as_owner { Settings::Save.call(Current.site, attributes: { ai_api_key: "sk-test-1" }) }
    Current.site.update_columns(ai_api_key_saved_at: nil)

    assert Current.site.reload.ai_api_key_set?
    assert_nil Current.site.ai_api_key_saved_on
  end

  test "the key's date is never an audited change and the key never reaches the event" do
    as_owner { Settings::Save.call(Current.site, attributes: { ai_api_key: "sk-test-1" }) }

    event = Audit::Event.find_by!(action: "settings.updated")
    assert_equal [ "not set", "set" ], event.field_changes["AI key"]
    assert_not_includes event.field_changes.keys, "ai_api_key_saved_at"
    assert_not_includes event.to_json, "sk-test-1"
  end

  test "an empty per-language hash is no site part: a languages-only actor still succeeds" do
    grant_to_branch_editors("languages.manage")

    result = as(users(:editor_branch)) do
      Settings::Save.call(Current.site, translations: { "en" => {}, "de" => { logo: nil } }, languages: reorder("de", "en", "es"))
    end

    assert result.ok?, result.errors.inspect
    assert_equal %w[de en es], Current.site.reload.locale_codes
  end

  test "a reorder does not rebuild the whole translation index" do
    create_page(title: "About")
    rebuilt = false
    with_singleton_override(Translations::StateIndex, :rebuild_all, -> { rebuilt = true }) do
      assert as_owner { Settings::Save.call(Current.site, languages: reorder("de", "en", "es")) }.ok?
      assert as_owner { Settings::Save.call(Current.site, translations: { "en" => { tagline: "T" } }, languages: reorder("en", "de", "es")) }.ok?
    end

    assert_not rebuilt
  end

  # What "leaves the site fields alone" means, exactly (final fix wave, Task 4):
  # a languages-only call assigns no site field, normalises none and records no
  # `settings.updated`. The ROW is still saved -- by `Locales::Configure#apply`,
  # for its `locales` -- and so still validated as a whole.
  test "a languages-only call assigns and audits no site field: a stored value only checked when it changes is neither a blocker nor rewritten" do
    grant_to_branch_editors("languages.manage")
    # `time_zone` is validated (and normalised) only when it changes.
    Current.site.update_columns(time_zone: "Nowhere/Land")

    result = as(users(:editor_branch)) { Settings::Save.call(Current.site, languages: reorder("de", "en", "es")) }

    assert result.ok?, result.errors.inspect
    assert_equal %w[de en es], Current.site.reload.locale_codes
    assert_equal "Nowhere/Land", Current.site.time_zone
    assert_not Audit::Event.exists?(action: "settings.updated")
    assert_equal 1, Audit::Event.where(action: "language.configured").count
  end

  test "a languages-only call is still refused by a stored value that is always validated, and names it" do
    grant_to_branch_editors("languages.manage")
    Current.site.update_columns(trash_retention_days: -1)

    result = as(users(:editor_branch)) { Settings::Save.call(Current.site, languages: reorder("de", "en", "es")) }

    assert_not result.ok?
    assert_match(/Trash retention days/, result.errors.to_sentence)
    assert_equal %w[en de es], Current.site.reload.locale_codes
    assert_not Audit::Event.exists?(action: %w[settings.updated language.configured])
  end

  test "changing the default language through attributes needs languages.manage" do
    grant_to_branch_editors("settings.manage")

    result = as(users(:editor_branch)) { Settings::Save.call(Current.site, attributes: { default_locale: "de" }) }

    assert result.denied?
    assert_equal "en", Current.site.reload.default_locale
    assert_equal 1, Audit::Event.where(action: "access.denied").count
    assert_equal "languages.manage", Audit::Event.find_by!(action: "access.denied").metadata["permission"]

    # Resending the stored default is no change, so settings.manage suffices.
    assert as(users(:editor_branch)) { Settings::Save.call(Current.site, attributes: { default_locale: "en" }) }.ok?
  end

  test "an API token actor on languages: is judged on its effective rights" do
    token = ApiToken.generate!(users(:one), group: access_control_groups(:admin)).first
    result = as(token, channel: :mcp) { Settings::Save.call(Current.site, languages: reorder("de", "en", "es")) }
    assert result.ok?, result.errors.inspect

    token = ApiToken.generate!(users(:one), group: access_control_groups(:read_only)).first
    result = as(token, channel: :mcp) { Settings::Save.call(Current.site, languages: reorder("es", "de", "en")) }
    assert result.denied?
    assert_equal %w[de en es], Current.site.reload.locale_codes
  end

  test "a stale language order is refused, not written over a language enabled meanwhile" do
    stale = SiteSetting.find(site_settings(:default).id)
    SiteSetting.find(stale.id).update!(locales: stale.locales + [ { "code" => "fr" } ])

    result = as_owner { Settings::Save.call(stale, languages: [ { "code" => "es" }, { "code" => "en" }, { "code" => "de" } ]) }

    assert_not result.ok?
    assert_includes result.errors.join, "must list exactly the enabled languages"
    assert_equal %w[en de es fr], SiteSetting.find(stale.id).locale_codes
  end

  # The rights are first checked against the copy the caller passed; the row
  # is then locked and re-read, and its stored default may differ from the
  # copy's. Resending the copy's default is then a default-language change.
  test "a default that changed behind the passed copy needs languages.manage after the lock" do
    grant_to_branch_editors("settings.manage")
    stale = SiteSetting.find(site_settings(:default).id)
    SiteSetting.find(stale.id).update_columns(default_locale: "de")

    result = as(users(:editor_branch)) { Settings::Save.call(stale, attributes: { default_locale: "en", time_zone: "Europe/Berlin" }) }

    assert result.denied?
    fresh = SiteSetting.find(stale.id)
    assert_equal "de", fresh.default_locale
    assert_not_equal "Europe/Berlin", fresh.time_zone
    assert_equal 1, Audit::Event.where(action: "access.denied").count
    assert_equal "languages.manage", Audit::Event.find_by!(action: "access.denied").metadata["permission"]
    assert_not Audit::Event.exists?(action: "settings.updated")
  end

  test "an actor holding both rights may resend a default that changed behind the passed copy" do
    grant_to_branch_editors("settings.manage", "languages.manage")
    stale = SiteSetting.find(site_settings(:default).id)
    SiteSetting.find(stale.id).update_columns(default_locale: "de")

    result = as(users(:editor_branch)) { Settings::Save.call(stale, attributes: { default_locale: "en" }) }

    assert result.ok?, result.errors.inspect
    assert_equal "en", SiteSetting.find(stale.id).default_locale
  end

  test "a site save locks the settings row before it writes, even when the copy was stale" do
    stale = SiteSetting.find(site_settings(:default).id)
    SiteSetting.find(stale.id).update!(locales: stale.locales + [ { "code" => "fr" } ])

    statements = capture_sql { as_owner { Settings::Save.call(stale, translations: { "en" => { title: "Locked title" } }) } }

    lock = statements.index { |sql| sql.include?("FROM \"site_settings\"") && sql.include?("FOR UPDATE") }
    write = statements.index { |sql| sql.start_with?("UPDATE \"site_settings\"") }
    assert lock, "the row is locked"
    assert write, "the row is written"
    assert_operator lock, :<, write
    assert_equal %w[en de es fr], SiteSetting.find(stale.id).locale_codes
  end

  test "every service locks the settings row exactly once" do
    site_settings(:default).update!(locales: [ { "code" => "en" }, { "code" => "de" }, { "code" => "es" } ])
    calls = {
      "Settings::Save" => -> { Settings::Save.call(Current.site, translations: { "en" => { title: "T" } }) },
      "Settings::Save with languages:" => -> { Settings::Save.call(Current.site, translations: { "en" => { title: "U" } }, languages: reorder("de", "en", "es")) },
      "Locales::Enable" => -> { Locales::Enable.call("fr") },
      "Locales::Disable" => -> { Locales::Disable.call("es") },
      "Locales::MakeDefault" => -> { Locales::MakeDefault.call("de") },
      "Locales::Configure" => -> { Locales::Configure.call([ { code: "en" }, { code: "de" }, { code: "fr" } ]) }
    }

    calls.each do |name, call|
      Current.site = nil
      statements = capture_sql { as_owner { call.call } }
      locks = statements.count { |sql| sql.include?("FROM \"site_settings\"") && sql.include?("FOR UPDATE") }
      assert_equal 1, locks, "#{name} locks the settings row once"
    end
  end
end
