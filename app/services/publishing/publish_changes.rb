module Publishing
  # Makes the rows of a published or scheduled page or post what the public
  # sees (drafts spec §4.3): takes the next copy, now or at a time. With no
  # time given, a change that is already scheduled keeps its time.
  #
  # Needs the right to publish, and nothing else: whoever may publish a page
  # may publish what is in it (D5). It writes no row of the page, the post or
  # a block, so no editor's base moves and no hold is asked.
  class PublishChanges < ApplicationService
    include ContentBlocks::Structure
    include KeepsAddresses
    include ShownSchedule

    NOT_PUBLISHED = "There is nothing on the site to change: publish it first".freeze

    def initialize(record, at: nil, shown_pending: NOT_ASKED, actor: Current.actor)
      @record = record
      @at = at
      @shown_pending = shown_pending
      @actor = actor
    end

    def call
      key = "#{prefix}s.publish"
      return denied(key, @record) unless authorize!(key, @record)

      version = nil
      @nothing = false
      @moved = false
      @record.class.transaction(requires_new: true) do
        # The page's row first, as every write that reads its blocks does.
        lock_owner(@record)
        next if @record.class.where(id: @record.id).pick(:published_at).nil?
        # What the dialog said about a schedule is no longer so (`ShownSchedule`).
        next @moved = true if schedule_moved?(@record, Time.current)

        # The mark may be set when nothing differs (typed and typed back):
        # then there is nothing to publish, and it is cleared. A new time for
        # changes that are already scheduled is something to publish. A record
        # with no copy (written around the services) has nothing to be the
        # same as: its first copy is taken.
        changes = Changes.of(@record)
        if changes.version && changes.none? && !(@at && Publishing.pending(@record))
          Publishing.clear_changes(@record)
          next @nothing = true
        end

        now = Time.current
        version = Version.take!(@record, live_at: @at || Publishing.pending(@record, now: now)&.live_at || now, by: actor_user, now: now, shown: true)
        record_event("#{prefix}.changes_published", subject: @record, coalesce: false,
          metadata: { "number" => version.number, "live_at" => version.live_at.iso8601, "scheduled" => version.live_at > now })
      end

      # The result does not say which of the two happened; the controller
      # tells by the baseline's number before and after.
      return failure(@record, [ MOVED ]) if @moved

      (version || @nothing) ? success(@record) : failure(@record, [ NOT_PUBLISHED ])
    rescue AddressTaken => e
      address_taken(@record, e)
    end

    private

    def prefix = @record.is_a?(Page) ? "page" : "post"
  end
end
