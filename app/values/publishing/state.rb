module Publishing
  # WHICH OF FIVE THINGS a page or post is, as far as publishing goes, and what
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
  #   `pending_at`; the state stays this one, as `:live` and `:live_with_changes`
  #   are two states only because the screens draw them differently). A scheduled
  #   record has the same ways out of a change as a live one, where the services
  #   accept them: with a copy pending (a change published with a time of its
  #   own on a scheduled record) it can be published again (now, or at another
  #   time), withdrawn, or discarded; with the mark alone, published or discarded.
  #   `discard_changes` is offered only where a copy is IN FORCE (a scheduled
  #   record's first copy is, from the moment it is taken): `DiscardChanges`
  #   answers "nothing to discard" for a record that has none, so it is not
  #   offered there.
  # - `:live`: a time that has passed, no copy pending, no mark.
  # - `:live_with_changes`: live, the mark, no copy pending.
  # - `:live_change_scheduled`: live, a copy pending (whatever the mark: more
  #   edits since are `changes?`). Its changes can be published again (now or
  #   at another time), withdrawn (`cancel_scheduled_change`: the pending
  #   copy goes, the rows stay as they are, as unpublished changes) or
  #   discarded, with or without edits since. Discarded only while a copy is
  #   IN FORCE: a record whose only copy is the pending one (written around
  #   the services, then given a scheduled change) is shown from its rows,
  #   and there is nothing to return to.
  #
  # A combination that should not exist (a mark on a draft) is answered as
  # the nearest true state and never raises: this runs on a page view.
  #
  # THE ONE PLACE for what a screen offers. The header's Publish, Schedule,
  # Edit schedule, Unpublish and Publish changes, every status chip and
  # `Publishable#status` ask this object (`status` is its one comparison of
  # `published_at` with the clock for a screen). The services and the usage
  # and path indexes compare `published_at` with a clock they are handed
  # themselves, where they need a time in a statement.
  #
  # `actions` is what makes sense in the state, BEFORE rights are applied
  # (`can?("pages.publish")` and the rest are the caller's):
  #
  # | state                  | actions                                              |
  # | :draft                 | publish, schedule                                    |
  # | :scheduled             | publish, schedule, then (+ publish_changes, discard_changes when changes? and no copy is pending) or (+ publish_changes, cancel_scheduled_change, and discard_changes when a copy is in force, when a copy is pending), unpublish |
  # | :live                  | unpublish                                            |
  # | :live_with_changes     | publish_changes, discard_changes, unpublish          |
  # | :live_change_scheduled | publish_changes, cancel_scheduled_change, (discard_changes when a copy is in force), unpublish |
  #
  # (`schedule` on a scheduled record is "Edit schedule"; `publish` on one is
  # "Publish now".)
  class State
    STATES = %i[draft scheduled live live_with_changes live_change_scheduled].freeze
    ACTIONS = %i[publish schedule publish_changes cancel_scheduled_change discard_changes unpublish].freeze

    # `pending_at:` hands over the answer to the one question that costs a
    # statement (fact 2 above), for a caller that has read the pending copies
    # of many records at once: the mind graph draws the fifth state on every
    # node, and asks once for all of them. Given (a time, or nil for "none"),
    # `pending_at` and `state` ask the database nothing. Not given, they read
    # it the first time, as before. A draft's is ignored either way.
    NOT_READ = Object.new.freeze
    private_constant :NOT_READ

    def self.of(record, now: Time.current, pending_at: NOT_READ) = new(record, now: now, pending_at: pending_at)

    def initialize(record, now: Time.current, pending_at: NOT_READ)
      @record = record
      @now = now
      @pending_at = pending_at unless pending_at.equal?(NOT_READ)
    end

    # "draft", "scheduled" or "live": the cheap answer lists and chips use,
    # from the time alone. The one place `published_at` meets the clock.
    def status
      if record.published_at.nil? then "draft"
      elsif record.published_at > now then "scheduled"
      else "live"
      end
    end

    def draft? = status == "draft"

    def scheduled? = status == "scheduled"

    # Live in any of its three states. No query.
    def live? = status == "live"

    # Exactly one of STATES.
    def state
      @state ||=
        if draft? then :draft
        elsif scheduled? then :scheduled
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
      when :scheduled then %i[publish schedule] + (pending_at ? pending_actions : changes_actions) + %i[unpublish]
      when :live then %i[unpublish]
      when :live_with_changes then changes_actions + %i[unpublish]
      when :live_change_scheduled then pending_actions + %i[unpublish]
      end
    end

    def action?(name) = actions.include?(name)

    private

    attr_reader :record, :now

    def changes_actions = changes? ? %i[publish_changes discard_changes] : []

    # A copy is pending, a live or a scheduled record's alike (whatever the
    # mark): published again, withdrawn, or discarded where one is in force.
    def pending_actions = %i[publish_changes cancel_scheduled_change] + (in_force? ? %i[discard_changes] : [])

    # Whether a copy is in force: what a discard returns to. Asked only for
    # a record with a change scheduled (one statement, the first time): one
    # whose ONLY copy is the pending one is shown from its rows, so there
    # is nothing to go back to, and withdrawing the change is its action.
    def in_force? = defined?(@in_force) ? @in_force : (@in_force = Publishing.in_force?(record, now: now))
  end
end
