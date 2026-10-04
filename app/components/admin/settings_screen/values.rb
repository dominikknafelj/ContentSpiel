module Admin
  module SettingsScreen
    # What the Settings form shows in each field: the stored record, unless
    # the form was just submitted and sent back (a 422, or a 409 on a stale
    # base), in which case what was TYPED -- the screen must never throw an
    # editor's text away because a save was refused. `submitted` is the
    # permitted `site_setting` params of that request, or nil on a plain GET.
    #
    # One object for the three cards that hold fields of the one form (Site,
    # Publishing, AI), so "typed beats stored" is decided in one place and
    # the cards can't drift. Never touches the AI key: it is not a field of
    # this form and is never rendered.
    class Values
      attr_reader :site, :submitted

      def initialize(site:, submitted: nil)
        @site = site
        @submitted = submitted
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

      def ai_provider = field(:ai_provider) { site.ai_provider }

      def ai_model = field(:ai_model) { site.ai_model }

      def remove_logo? = ActiveModel::Type::Boolean.new.cast(submitted&.dig(:remove_logo)) || false

      # The stored logo. After a refused save the record in memory holds the
      # NEW, unsaved attachment (which has no URL to draw), so the screen
      # shows the one in the database; a chosen file can't be put back into a
      # file input, and says so by the input being empty again.
      def logo
        submitted? ? SiteSetting.find(site.id).logo : site.logo
      end

      # `[[name, url], ...]` in the order shown, always at least one (empty)
      # row. Typed rows come back exactly as typed, half-filled ones included.
      def social_rows
        rows =
          if submitted&.key?(:social_links)
            raw = submitted[:social_links]
            raw = raw.to_h.sort_by { |index, _| index.to_i }.map(&:last) unless raw.is_a?(Array)
            raw.map { |row| [ row[:name].to_s, row[:url].to_s ] }
          else
            site.social_links.to_a
          end
        rows.presence || [ [ "", "" ] ]
      end

      private

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
