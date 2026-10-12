module Publishing
  # WHICH OF SIX THINGS a page or post is, as far as publishing goes, and what
  # may be done to it. The one place that says so: the editor's header (its
  # chip and its buttons), the page tree's and the posts list's marks and the
  # dashboard's list ask THIS object and derive nothing of their own.
  #
  # Derived, never stored: from three facts, each a read the caller has
  # already made or makes once.
  #
  # 1. THE TIME, `published_at`: none (a draft), later than now (scheduled),
  #    or not (live).
  # 2. A COPY PENDING: a change published with a time of its own, not yet in
  #    force (`Publishing.pending`). One statement, made only when asked
  #    (`pending_at`, `state`, `actions` for a record that has a time), never
  #    for `changes?`, so a list of two hundred rows asks nothing per row.
  # 3. THE MARK, `unpublished_changes_at`: the rows have moved on from the
  #    newest copy (drafts spec §4.4). It may be set when the net difference is
  #    nothing (typed and typed back; `Publishing::Changes` finds out).
  #
  # The states, and the combinations that stand for them:
  #
  # - `:draft`: no time. Any mark or pending copy it kept from before is
  #   ignored. An unpublished record (it had a time once) is a draft here too:
  #   the header says "Draft" for both today, and telling them apart would
  #   cost a read of the copies for no screen that wants it.
  # - `:scheduled`: a time in the future (a mark is `changes?`, a pending copy
  #   `pending_at`; the state stays this one).
  # - `:live`: a time that has passed, no copy pending, no mark.
  # - `:live_with_changes`: live, the mark, no copy pending.
  # - `:live_change_scheduled`: live, a copy pending (whatever the mark: more
  #   edits since are `changes?`).
  #
  # A combination that should not exist (a mark on a draft) is answered as
  # the nearest true state and never raises: this runs on a page view.
  #
  # `actions` is what makes sense in the state, BEFORE rights are applied
  # (`can?("pages.publish")` and the rest are the caller's):
  #
  # | state                  | actions                                              |
  # | :draft                 | publish, schedule                                    |
  # | :scheduled             | publish, schedule, unpublish (+ publish_changes, discard_changes when changes?) |
  # | :live                  | unpublish                                            |
  # | :live_with_changes     | publish_changes, discard_changes, unpublish          |
  # | :live_change_scheduled | unpublish (+ publish_changes, discard_changes when changes?) |
  #
  # (`schedule` on a scheduled record is "Edit schedule"; `publish` on one is
  # "Publish now".)
  class State
    STATES = %i[draft scheduled live live_with_changes live_change_scheduled].freeze
    ACTIONS = %i[publish schedule publish_changes discard_changes unpublish].freeze

    def self.of(record, now: Time.current) = new(record, now: now)

    def initialize(record, now: Time.current)
      @record = record
      @now = now
    end

    # Exactly one of STATES.
    def state
      @state ||=
        if record.published_at.nil? then :draft
        elsif record.published_at > now then :scheduled
        elsif pending_at then :live_change_scheduled
        elsif changes? then :live_with_changes
        else :live
        end
    end

    # The rows have moved on from what is published: a time and the mark.
    # `Publishable#unpublished_changes?` is this, and `Publishable.with_unpublished_changes` its SQL.
    def changes? = record.published_at.present? && record.unpublished_changes_at.present?

    # When the copy waiting for its time comes into force, or nil. A draft
    # has none whatever copies it kept. One statement, the first time.
    def pending_at
      return nil if record.published_at.nil?

      defined?(@pending_at) ? @pending_at : (@pending_at = Publishing.pending(record, now: now)&.live_at)
    end

    def actions
      case state
      when :draft then %i[publish schedule]
      when :scheduled then %i[publish schedule] + changes_actions + %i[unpublish]
      when :live then %i[unpublish]
      when :live_with_changes, :live_change_scheduled then changes_actions + %i[unpublish]
      end
    end

    def action?(name) = actions.include?(name)

    private

    attr_reader :record, :now

    def changes_actions = changes? ? %i[publish_changes discard_changes] : []
  end
end
