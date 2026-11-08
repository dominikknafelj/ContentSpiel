module Admin
  module SettingsScreen
    # What the Settings form shows in each field: the stored record, unless
    # the form was just submitted and sent back (a 422, or a 409 on a stale
    # base), in which case what was TYPED -- the screen must never throw an
    # editor's text away because a save was refused. `submitted` is the
    # permitted `site_setting` params of that request, or nil on a plain GET.
    #
    # One object for the cards that hold fields of the one form, so "typed
    # beats stored" is decided in one place and the cards can't drift. Never
    # touches the AI key or the mail login: neither is a field of this form,
    # and neither is ever rendered.
    #
    # `stored:` is the row as saved. After a refused save `site` holds what
    # was typed, so the view reads the row again and hands it in; on a plain
    # load the two are one record.
    class Values
      attr_reader :site, :submitted, :stored

      def initialize(site:, submitted: nil, stored: nil)
        @site = site
        @submitted = submitted
        @stored = stored || site
      end

      def submitted? = !submitted.nil?

      # A language's title or tagline: literal per language (never through a
      # fallback -- a blank German tagline must show as blank, not as the
      # English one).
      def text(code, field)
        typed = submitted&.dig(:translations, code.to_s)
        return typed[field].to_s if typed&.key?(field)

        site.public_send(field, locale: code.to_s)
      end

      def time_zone = field(:time_zone) { selected_stored_zone }

      def trash_retention_days = field(:trash_retention_days) { site.trash_retention_days }

      def form_keep_days = field(:form_keep_days) { site.form_keep_days }

      def ai_provider = field(:ai_provider) { site.ai_provider }

      def ai_model = field(:ai_model) { site.ai_model }

      # The Mail card's five fields of this form (never the login, which is
      # not a field of it and never rendered).
      def mail(name) = field(name) { site.public_send(name) }

      # The Images card's fields (`ImagesCardComponent::FIELDS`). The widths
      # are one text of comma-separated numbers; typed text comes back as typed.
      def image(name)
        return field(name) { Array(site.image_widths).join(", ") } if name == :image_widths

        field(name) { site.public_send(name) }
      end

      def remove_logo? = ActiveModel::Type::Boolean.new.cast(submitted&.dig(:remove_logo)) || false

      # The stored logo. After a refused save the record in memory holds the
      # NEW, unsaved attachment (which has no URL to draw), so the screen
      # shows the saved row's; a chosen file can't be put back into a file
      # input, and says so by the input being empty again.
      def logo = stored.logo

      # `[[name, url], ...]` in the order shown; empty for a site with no
      # links ("+ Add link" is then all there is). Typed rows come back exactly
      # as typed, half-filled ones included. A submitted form that carried the
      # `social_links_present` marker says which rows it HAD, so a save refused
      # for another reason (a blank title) keeps a list the editor emptied
      # empty, rather than bringing the stored links back.
      def social_rows
        return site.social_links.to_a unless submitted&.key?(:social_links) || submitted&.key?(:social_links_present)

        raw = submitted[:social_links]
        raw = raw.to_h.sort_by { |index, _| index.to_i }.map(&:last) if raw.respond_to?(:to_h) && !raw.is_a?(Array)
        Array(raw).select { |row| row.respond_to?(:key?) }.map { |row| [ row[:name].to_s, row[:url].to_s ] }
      end

      # The Languages card's rows, `[{ code:, fallback: }]` in the order shown,
      # `fallback` the ONE code the row's select shows ("" for none). Typed
      # beats stored, like every other field: after a refused or stale save the
      # order and the selects come back as typed (a code the form didn't carry
      # keeps its stored place at the end; one that is no longer enabled is
      # dropped). The stored side is read from the database (`attribute_in_
      # database`), not the in-memory row: a refused `Locales::Configure` leaves
      # the typed entries assigned to it.
      #
      # A language stored with several fallbacks shows the FIRST, since the
      # select holds one; the others are dropped only when that row's select
      # is changed and saved
      # (`Admin::SettingsController#language_arguments` compares the posted
      # value with this same first entry).
      def language_rows
        stored = Array(site.attribute_in_database(:locales)).map { |entry| entry.to_h.stringify_keys }
        typed = Array(submitted&.dig(:languages)).select { |row| row.respond_to?(:key?) && row[:code].present? }
        typed_codes = typed.map { |row| row[:code].to_s }
        codes = stored.map { |entry| entry["code"] }
        ordered = (typed_codes & codes) + (codes - typed_codes)
        ordered.map do |code|
          typed_row = typed.find { |row| row[:code].to_s == code }
          stored_first = Array(stored.find { |entry| entry["code"] == code }&.dig("fallbacks")).first.to_s
          { code: code, fallback: typed_row&.key?(:fallback) ? typed_row[:fallback].to_s : stored_first }
        end
      end

      # The `data-field-name` of every wrapper whose typed value differs from
      # the stored one: what a refused or stale save left unsaved, which the
      # browser cannot tell (its baseline is what was typed). Empty on a plain
      # load. Per language (`title.de`), per row (`languages.de.fallback`),
      # and the lists as one field each (`social_links`, `language_order`).
      # A chosen logo file is not among them: it cannot be put back into the
      # file input, so nothing of it is still unsaved; Remove logo is.
      def changed_fields
        return [] unless submitted?

        saved = Values.new(site: stored)
        names = ::Locales.enabled.flat_map do |code|
          %i[title tagline].filter_map { |name| "#{name}.#{code}" if text(code, name).to_s != saved.text(code, name).to_s }
        end
        names += SINGLE_FIELDS.select { |name| single(name) != saved.single(name) }.map(&:to_s)
        names << "logo" if remove_logo?
        names << "social_links" if social_rows != saved.social_rows.map { |name, url| [ name.to_s, url.to_s ] }
        names + language_changes(saved)
      end

      # "saved" for a wrapper `changed_fields` names, else nil: the value of
      # its `data-save-bar-changed`.
      def saved_change(name) = ("saved" if changed_names.include?(name.to_s))

      protected

      # One field's value as compared: what its control shows. The widths as
      # their numbers, so "320,640" typed back as "320, 640" is no change; a
      # blank security as the option the card shows ticked for it, which is
      # what the form sends back.
      def single(name)
        value = public_send(*SINGLE_READERS.fetch(name) { [ :mail, name ] }).to_s
        case name
        when :image_widths then value.scan(/\d+/)
        when :mail_security then MailCardComponent::SECURITIES.include?(value) ? value : ::MailSettings::DEFAULT_SECURITY
        else value
        end
      end

      private

      SINGLE_FIELDS = %i[time_zone trash_retention_days form_keep_days ai_provider ai_model
        mail_server mail_port mail_security mail_sender_name mail_sender_address
        image_format image_quality_webp image_quality_avif image_widths image_max_upload_mb].freeze
      SINGLE_READERS = {
        time_zone: [ :time_zone ], trash_retention_days: [ :trash_retention_days ], form_keep_days: [ :form_keep_days ],
        ai_provider: [ :ai_provider ], ai_model: [ :ai_model ],
        image_format: [ :image, :image_format ], image_quality_webp: [ :image, :image_quality_webp ], image_quality_avif: [ :image, :image_quality_avif ],
        image_widths: [ :image, :image_widths ], image_max_upload_mb: [ :image, :image_max_upload_mb ]
      }.freeze

      def changed_names = @changed_names ||= changed_fields

      # The order as one field, each row's fallback as its own.
      def language_changes(saved)
        typed = language_rows
        kept = saved.language_rows
        names = typed.map { |row| row[:code] } == kept.map { |row| row[:code] } ? [] : [ "language_order" ]
        names + typed.filter_map do |row|
          before = kept.find { |entry| entry[:code] == row[:code] }
          "languages.#{row[:code]}.fallback" if before && before[:fallback] != row[:fallback]
        end
      end

      def field(name)
        return submitted[name].to_s if submitted&.key?(name)

        yield
      end

      def selected_stored_zone
        stored = site.time_zone.to_s
        ::ActiveSupport::TimeZone::MAPPING.key(stored) || stored
      end
    end
  end
end
