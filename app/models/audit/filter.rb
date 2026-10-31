module Audit
  # The audit log's filters, read from request params (design pass round 3,
  # Task 15): User, Action, Type, Channel, a Date preset (Today / 7 / 30 / 90
  # days / Custom with From and To) and the subject a record's "Activity" link
  # names. Every value is validated here and reaches SQL only as a bound
  # parameter; anything that isn't a valid value is dropped -- "all" -- never
  # an error (a typo, a stale link, a probing request).
  #
  # Dates are the SITE's days: a preset is computed from `Time.zone.today`
  # (requests run inside the site time zone) and a typed day spans its own
  # midnight to midnight, so "Today" is today where the editors are. They bound
  # `last_occurred_at`, the column the list is ordered by (a coalesced span is
  # placed by when it last extended), which `index_audit_events_on_recent`
  # serves; `From` after `To` is swapped rather than answered empty. Indexes:
  # the date range and the ordering ride `index_audit_events_on_recent`, a
  # subject filter `index_audit_events_on_subject_and_newest`; user and action
  # have indexes keyed on `occurred_at` (the planner picks between them and the
  # recent index), and channel has none -- it filters the rows an ordered scan
  # of the recent index already visits, which is cheap for the three-way split.
  class Filter
    RANGES = %w[today 7 30 90 custom].freeze
    CHANNELS = %w[admin mcp other].freeze
    MAX_ACTION_LENGTH = 100

    # The subject types any cataloged event can carry, keyed by the polymorphic
    # `subject_type` string actually stored on the row (`AccessControl::Group`'s
    # own table-name comment explains why its type is the full namespaced name).
    # The filter's whitelist and the Type drop-down, so the two can't drift.
    # `Media::Asset` was `MediaAsset` before the media library: a pre-rename row
    # still reads that (`Audit::Event::LEGACY_POLYMORPHIC_TYPES`), so filtering by
    # "Media asset" matches both.
    SUBJECT_TYPES = {
      "Post" => "Post",
      "Page" => "Page",
      "ContentBlock" => "Block",
      "AccessControl::Group" => "Group",
      "Tag" => "Tag",
      "User" => "User",
      "Invitation" => "Invitation",
      "SiteSetting" => "Settings",
      "ApiToken" => "API token",
      "Media::Asset" => "Media asset"
    }.freeze

    # Years outside this are a typo or a probe, not a date anyone filters by.
    YEARS = (1970..2200)

    attr_reader :user_id, :event_action, :subject_type, :subject_id, :channel, :range

    def initialize(params, today: Time.zone.today)
      @today = today
      @user_id = integer(params[:user_id])
      @event_action = params[:event_action].to_s.presence&.first(MAX_ACTION_LENGTH)
      @subject_type = params[:subject_type].to_s if SUBJECT_TYPES.key?(params[:subject_type].to_s)
      # A subject id alone is ambiguous (a Post and a Page can share one).
      @subject_id = integer(params[:subject_id]) if @subject_type
      @channel = params[:channel].to_s if CHANNELS.include?(params[:channel].to_s)
      from = date(params[:from])
      to = date(params[:to])
      # `from`/`to` without a preset are the pre-preset links: a custom range.
      @range = RANGES.include?(params[:range].to_s) ? params[:range].to_s : (("custom" if from || to))
      from, to = to, from if from && to && from > to
      @from = from
      @to = to
    end

    def custom? = range == "custom"

    # The two typed days, as the form shows them (custom only).
    def from = (@from if custom?)

    def to = (@to if custom?)

    def subject? = subject_id.present?

    def active? = to_params.any?

    # The normalised values, as query params, for every link that must keep the
    # filters (the pager, the event page, its Older/Newer): only what is valid.
    def to_params
      {
        "user_id" => user_id, "event_action" => event_action, "subject_type" => subject_type, "subject_id" => subject_id,
        "channel" => channel, "range" => range, "from" => from&.iso8601, "to" => to&.iso8601
      }.compact.transform_values(&:to_s)
    end

    def scope(base = Event.all)
      scope = base
      scope = scope.where(user_id:) if user_id
      scope = scope.where(action: event_action) if event_action
      scope = scope.where(subject_type: stored_subject_types) if subject_type
      scope = scope.where(subject_id:) if subject_id
      scope = channel_scope(scope)
      lower, upper = bounds
      scope = scope.where(last_occurred_at: lower..) if lower
      scope = scope.where(last_occurred_at: ..upper) if upper
      scope
    end

    # The order of the list, and of an event's Older/Newer: newest span end first.
    def self.ordered(relation) = relation.order(last_occurred_at: :desc, id: :desc)

    private

    def stored_subject_types
      [ subject_type, *Audit::Event::LEGACY_POLYMORPHIC_TYPES.filter_map { |legacy, current| legacy if current == subject_type } ]
    end

    def channel_scope(scope)
      case channel
      when "admin", "mcp" then scope.where(channel:)
      when "other" then scope.where.not(channel: %w[admin mcp]).or(scope.where(channel: nil))
      else scope
      end
    end

    # `[lower, upper]` instants (either may be open) for the chosen range.
    def bounds
      case range
      when "today" then [ midnight(@today), nil ]
      when "7", "30", "90" then [ midnight(@today - (range.to_i - 1)), nil ]
      when "custom" then [ (midnight(@from) if @from), (midnight(@to).end_of_day if @to) ]
      else [ nil, nil ]
      end
    end

    def midnight(day) = day.in_time_zone.beginning_of_day

    def integer(value)
      string = value.to_s
      string.match?(/\A\d{1,18}\z/) ? string.to_i : nil
    end

    # `Date.iso8601` raises on anything that isn't a real `YYYY-MM-DD`.
    def date(value)
      return if value.blank?

      parsed = Date.iso8601(value.to_s)
      YEARS.cover?(parsed.year) ? parsed : nil
    rescue ArgumentError, TypeError
      nil
    end
  end
end
