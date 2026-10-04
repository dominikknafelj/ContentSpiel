class SiteSetting < ApplicationRecord
  extend Mobility

  has_one_attached :logo

  # The site's name and tagline, per language (translation helpers spec
  # §5): Mobility jsonb columns like every other translated one, read on
  # the public site through `Locales.read` (`ThemeHelper#translated`), so a
  # language without its own falls back like a page title does. Every
  # other column here is a single value for the whole site, the same in
  # every language.
  translates :title, :tagline

  # Which version of the default-language title/tagline each translation
  # was saved against (translation helpers spec §3.2) -- the tracked
  # fields are exactly the two `translates` names above.
  include Translations::Tracker
  tracks_translations

  # The AI translation key (translation helpers spec §6.2): encrypted at
  # rest with Active Record encryption (keys: config/application.rb), and
  # never rendered (the Settings form only ever says whether one is set),
  # logged (the `_key` entry in `filter_parameters`) or audited
  # (`Audit::Snapshot::NEVER_STORED`).
  encrypts :ai_api_key

  # A select's "None" posts "", a pasted key often carries a trailing
  # newline: stored as nil / stripped instead.
  normalizes :ai_provider, :ai_model, :ai_api_key, with: ->(value) { value.to_s.strip.presence }

  # Only a provider somebody registered (`AI::Providers`); blank means AI
  # is off. Checked only when it changes, like `time_zone` below: a plugin
  # provider whose plugin was later removed mustn't block an unrelated
  # title edit -- `AI.configured?` already treats it as not set up.
  validate :ai_provider_is_registered, if: :will_save_change_to_ai_provider?

  validate :only_one_record_exists, on: :create

  # The title is the site's one required translated field, and only in the
  # default language: that's the one every other language falls back to
  # (`Locales.fallback_chain`), so a site with a title there always has a
  # name to show. Read from the raw jsonb, never through the plain Mobility
  # reader, which reads the *ambient* locale (`Page#title_present_in_any_
  # locale`'s comment has the incident) -- a German-only save mustn't be
  # judged on the German title. A blank title in another language is a
  # missing translation (`Translations::Status`), not an error.
  validate :title_present_in_default_locale

  # Runs before the title check above, so a new default inherits a name
  # instead of being refused for not having one -- see the method.
  before_validation :carry_translations_into_new_default_locale, if: :will_save_change_to_default_locale?

  validate :locales_are_well_formed
  validate :social_links_are_safe, if: :will_save_change_to_social_links?
  validate :default_locale_is_enabled

  # The zone every CS Studio and MCP time is shown and parsed in (dashboard
  # spec §5); storage stays UTC. Stored as a Rails zone name ("Berlin"):
  # an IANA identifier ("Europe/Berlin") is accepted but normalised to its
  # Rails name first (`#normalize_time_zone`), because the Settings select's
  # option values are Rails names -- a stored "Europe/Berlin" matched no
  # option, the browser showed the first one instead, and the next autosave
  # of *any* field (the form resends everything) silently wrote
  # "International Date Line West" back (final fix wave, I2).
  #
  # Validated only when it changes: a value written around the model that
  # no Rails name covers (raw SQL, a restored backup) is still shown and
  # resent unchanged by the form (`Admin::SettingsFormComponent#
  # time_zone_options`), and mustn't block an unrelated title edit --
  # `#effective_time_zone` is what keeps an unknown one from 500ing.
  before_validation :normalize_time_zone
  validate :time_zone_is_known, if: :will_save_change_to_time_zone?

  # 0 means "never" (trash spec §3.1/§7: the sweep job skips a site with this
  # set to 0) -- so this is a plain non-negative check, not `greater_than: 0`.
  validates :trash_retention_days, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  after_commit :reset_cached_state

  # Titled in the new row's own default language, not the ambient
  # `Mobility.locale` -- which, the first time this runs on a public
  # request, is whatever language that request happened to be in.
  def self.instance
    first || create! { |site| Mobility.with_locale(site.default_locale) { site.title = "My Site" } }
  end

  # The one rule for a social link's URL: an absolute http/https/mailto
  # URL. Enforced on save (`#social_links_are_safe`) and again by the
  # public footer (`ThemeHelper#safe_social_links`) as defence in depth for a
  # row written around validations.
  SOCIAL_LINK_SCHEMES = %w[http https mailto].freeze

  def self.safe_social_link?(url)
    scheme = URI.parse(url.to_s.strip).scheme
    scheme.present? && SOCIAL_LINK_SCHEMES.include?(scheme.downcase)
  rescue URI::InvalidURIError
    false
  end

  # The zone `Admin::BaseController`/`McpController`'s own `use_site_time_
  # zone` actually wraps every request in -- never the bare `time_zone`
  # attribute, which `#time_zone_is_known` only guards on a save made
  # *through this model*. A row written around it (a raw-SQL migration,
  # e.g. `20260926120000`'s own `INSERT`/`UPDATE` pattern, or a restored
  # backup) could still hold something `ActiveSupport::TimeZone` doesn't
  # recognise, and `Time.use_zone` raises `ArgumentError` on exactly that --
  # which, wrapping *every* admin and MCP request, would otherwise take the
  # whole surface down with no in-app way to fix it (the Settings form
  # itself is behind the same wrapper). Falling back to UTC instead keeps
  # both up, readable in the one zone every stored time is actually in.
  def effective_time_zone
    ActiveSupport::TimeZone[time_zone.to_s] || ActiveSupport::TimeZone["UTC"]
  end

  # Whether a key is stored, read off the raw column -- never decrypting
  # it. Everything that only needs to know *that* there's a key (the
  # Settings form's "API key: set", `AI.configured?`) asks this, so a key
  # the current encryption keys can't read (keys lost, rotated, or a
  # production boot without them) still shows as set and can still be
  # removed or replaced, instead of 500ing the Settings screen that's the
  # only way to fix it. Only `AI.provider`, which actually needs the
  # plaintext, decrypts.
  def ai_api_key_set? = ai_api_key_before_type_cast.present?

  # The day the stored key was saved, in the site time zone (what the Settings
  # screen prints as "added 2 Oct"); nil when there is no key or it predates
  # the column. Never decrypts anything.
  def ai_api_key_saved_on
    return nil unless ai_api_key_set?

    ai_api_key_saved_at&.in_time_zone(effective_time_zone)&.to_date
  end

  def locale_codes
    Array(locales).map { |entry| entry["code"].to_s }
  end

  def locale_entry(code)
    Array(locales).find { |entry| entry["code"].to_s == code.to_s }
  end

  # The row-by-row shape a name/URL fieldset naturally submits (any row can
  # be left blank) -- this is the one place that shape turns into the plain
  # `{ name => url }` hash `social_links` itself stores, so every caller
  # (the setup wizard's own site step, `Admin::SettingsController`) shares
  # the exact same "drop the empty rows" rule instead of each hand-keeping
  # its own copy (formerly `SetupController#site_params` alone).
  def social_link_rows=(rows)
    links = Array(rows).filter_map do |row|
      name, url = row[:name].to_s.strip, row[:url].to_s.strip
      [ name, url ] if name.present? && url.present?
    end
    self.social_links = links.to_h
  end

  private

  def ai_provider_is_registered
    return if ai_provider.blank? || AI::Providers.find(ai_provider)

    errors.add(:ai_provider, "isn't an available provider")
  end

  def only_one_record_exists
    errors.add(:base, "only one SiteSetting may exist") if SiteSetting.exists?
  end

  # `Translations::Tracker`'s hooks: this row *is* where the site's
  # languages live, so it reads them off itself rather than through
  # `Current.site` -- which, while `.instance` is still creating this row,
  # would try to create it again.
  def translation_primary_locale = default_locale.to_s

  def translation_target_locales = locale_codes - [ translation_primary_locale ]

  def title_present_in_default_locale
    errors.add(:title, :blank) if read_attribute(:title).to_h[default_locale.to_s].blank?
  end

  # A new default language with no title (or tagline) of its own takes the
  # previous default's, so the site keeps the name it had. Two places would
  # otherwise get stuck:
  # - the setup wizard asks for the title (site step) *before* the default
  #   language (languages step), so the title was typed in the old default,
  #   and `#title_present_in_default_locale` would refuse the languages step
  #   outright;
  # - CS Studio's Settings autosaves the whole form on every change, so a
  #   refused default language would be resent, and refused again, with
  #   every later edit until someone put the select back.
  # Public output doesn't change: the old default's value was already what
  # the new default fell back to. A value the new default already has is
  # kept as it is.
  def carry_translations_into_new_default_locale
    previous = default_locale_in_database.to_s
    current = default_locale.to_s
    # An unknown or not-enabled language is `#default_locale_is_enabled`'s
    # (or `#locales_are_well_formed`'s) to refuse -- and Mobility raises on
    # writing one outside `I18n.available_locales`.
    return if previous.blank? || previous == current
    return unless locale_codes.include?(current) && I18n.available_locales.map(&:to_s).include?(current)

    self.class.translation_columns.each do |field|
      values = read_attribute(field).to_h
      next if values[current].present? || values[previous].blank?

      Mobility.with_locale(current) { public_send("#{field}=", values[previous]) }
    end
  end

  # Final fix wave (E): a link the footer can't render -- `github.com/dana`
  # typed without its scheme, most often -- is an error where it's typed,
  # rather than saving fine and then silently never appearing.
  def social_links_are_safe
    social_links.to_h.each do |name, url|
      errors.add(:social_links, "#{name} must start with https://, http:// or mailto:") unless self.class.safe_social_link?(url)
    end
  end

  def locales_are_well_formed
    codes = locale_codes
    return errors.add(:locales, "must enable at least one language") if codes.empty?

    unsupported = codes - ::SUPPORTED_LOCALES.keys
    errors.add(:locales, "contains an unsupported language: #{unsupported.join(', ')}") if unsupported.any?
    errors.add(:locales, "lists a language twice") if codes.uniq.size != codes.size

    Array(locales).each do |entry|
      missing = Array(entry["fallbacks"]).map(&:to_s) - codes
      errors.add(:locales, "#{entry['code']} falls back to a language that isn't enabled: #{missing.join(', ')}") if missing.any?
    end
  end

  # PagesController and config/sitemap.rb both use this value directly as a
  # locale to render/link pages in, with no fallback -- an admin typing
  # anything other than one of the site's enabled locales would make every
  # page unreachable at the site's own root.
  def default_locale_is_enabled
    errors.add(:default_locale, "must be one of the enabled languages") unless locale_codes.include?(default_locale.to_s)
  end

  # `MAPPING` is Rails name => IANA identifier; `key` finds the first Rails
  # name for an identifier (several share one -- "Edinburgh" and "London"
  # are both "Europe/London" -- and any of them is the same zone). A value
  # that already is a Rails name, or that no Rails name covers, is kept.
  def normalize_time_zone
    rails_name = ActiveSupport::TimeZone::MAPPING.key(time_zone.to_s)
    self.time_zone = rails_name if rails_name
  end

  def time_zone_is_known
    errors.add(:time_zone, "isn't a known time zone") unless ActiveSupport::TimeZone.all.any? { |zone| zone.name == time_zone }
  end

  # Both caches hold a copy of this row's state: Current.site the whole row,
  # Setup's latch whether setup is done. Resetting after commit (not after
  # save) so a rolled-back change never leaves them pointing at data that no
  # longer exists.
  def reset_cached_state
    Current.site = nil
    Setup.reset!
  end
end
