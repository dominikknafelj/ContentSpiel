module Admin
  module DashboardScreen
    # One record on a dashboard list (dashboard spec §4.2-§4.3): a page, a
    # post or a library image, linked to its editor (an image to its detail
    # panel in the Media module), with its type, its publish state (pages
    # and posts only -- an image has none), a time and who last changed it.
    #
    # Everything here reads what `Dashboard::Feed` already loaded -- titles
    # are jsonb columns, a post's type label comes from the in-memory
    # `ContentTypes` registry, an image's thumbnail from the variants the
    # feed preloads, and `change` is the feed's own `#last_change` hash with
    # its actor and user preloaded -- so a row never costs a query of its
    # own (the dashboard's constant-query test pins this).
    #
    # `time:` names which moment the row shows: `:published_at` for the
    # scheduled lists (when it goes live), `:last_change` for "Recently
    # edited by you" (when *I* last changed it -- the newest event's time,
    # not `updated_at`, which a later system touch could move), otherwise
    # `:updated_at`.
    class RowComponent < Admin::AdminComponent
      TIME_FORMAT = "%b %-d, %Y %H:%M".freeze

      def initialize(record:, change:, time: :updated_at)
        @record = record
        @change = change
        @time = time
      end

      def title = record.title.presence || "Untitled"

      def image? = record.is_a?(Media::Asset)

      def type_label
        case record
        when Page then "Page"
        when Post then record.definition&.label || record.content_type.to_s.humanize
        else "Image"
        end
      end

      def path
        case record
        when Page then helpers.admin_page_path(record, **url_options)
        when Post then helpers.admin_post_path(record, **url_options)
        else helpers.admin_medium_path(record, **url_options)
        end
      end

      def at
        time == :last_change ? change&.dig(:at) : record.public_send(time)
      end

      def time_prefix = time == :published_at ? "Goes live" : "Updated"

      def formatted_at = at.strftime(TIME_FORMAT)

      # Spec §4.3's "Who changed it": the newest event's person -- for a
      # change made through an API token, the token's user, never "API
      # token #7" (the audit log is where that detail lives) -- and nothing
      # at all when the record has no event (saved straight through the
      # model, or before the audit log existed).
      #
      # The person is the event's `user_id`, which `Audit.record` fills for
      # a user and a token alike and which outlives both (`audit_events`
      # has no foreign key on it -- final fix wave, M4): a deleted token
      # still names its user, and a deleted user reads "by a deleted user",
      # not "by System". Only an event with no `user_id` -- a nil actor on
      # a trusted channel -- is the system's.
      def changed_by
        return if change.nil?
        return "by System" if change[:user_id].nil? && change[:user].nil?

        change[:user] ? "by #{change[:user].email_address}" : "by a deleted user"
      end

      private

      attr_reader :record, :change, :time

      # Keeps the editing language across navigation, like every other
      # admin link -- `admin_url_options` is a controller helper, absent
      # when a component is rendered on its own (component tests).
      def url_options = helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options : {}
    end
  end
end
