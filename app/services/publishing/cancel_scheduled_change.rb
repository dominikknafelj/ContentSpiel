module Publishing
  # Withdraws a change that was published with a time and has not come into
  # force ("Cancel scheduled change", `Publishing::State`'s
  # `cancel_scheduled_change`): the pending copy goes, the site keeps showing
  # the copy in force, and the rows stay exactly as they are. What was
  # scheduled is therefore unpublished changes again wherever the rows differ
  # from the copy in force, and the mark says so; where they do not differ
  # (typed and typed back since) it is cleared.
  #
  # Needs the right to publish, as scheduling the change did. It writes no
  # row of the page, the post or a block, so no editor's base moves and no
  # hold is asked. The record's row lock first, as taking a copy takes it.
  class CancelScheduledChange < ApplicationService
    include ContentBlocks::Structure
    include ShownSchedule

    NOTHING = "No change is scheduled".freeze

    def initialize(record, shown_pending: NOT_ASKED, actor: Current.actor)
      @record = record
      @shown_pending = shown_pending
      @actor = actor
    end

    def call
      key = "#{prefix}s.publish"
      return denied(key, @record) unless authorize!(key, @record)

      @moved = false
      cancelled = @record.class.transaction(requires_new: true) do
        lock_owner(@record)
        next false if @record.class.where(id: @record.id).pick(:published_at).nil?

        now = Time.current
        # The change the dialog named is not the one that waits now (`ShownSchedule`).
        next @moved = true if schedule_moved?(@record, now)

        number = Version.withdraw_pending!(@record, now: now).last
        next false if number.nil?

        # The images only the withdrawn copy showed are no longer in use.
        Media::UsageIndex.refresh_published(@record, now: now)
        # A record whose only copy was the pending one is shown from its
        # rows: nothing of it is unpublished.
        current = Publishing.current(@record, now: now)
        if current && !Changes.new(@record, current).none?
          Publishing.note_change(@record, now: now)
        else
          Publishing.clear_changes(@record)
        end
        record_event("#{prefix}.scheduled_change_cancelled", subject: @record, metadata: { "number" => number }, coalesce: false)
        true
      end

      return failure(@record, [ MOVED ]) if @moved

      cancelled ? success(@record) : failure(@record, [ NOTHING ])
    end

    private

    def prefix = @record.is_a?(Page) ? "page" : "post"
  end
end
