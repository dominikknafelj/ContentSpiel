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

    NOT_PUBLISHED = "There is nothing on the site to change: publish it first".freeze

    def initialize(record, at: nil, actor: Current.actor)
      @record = record
      @at = at
      @actor = actor
    end

    def call
      key = "#{prefix}s.publish"
      return denied(key, @record) unless authorize!(key, @record)

      version = nil
      lost = []
      @record.class.transaction(requires_new: true) do
        # The page's row first, as every write that reads its blocks does.
        lock_owner(@record)
        next if @record.class.where(id: @record.id).pick(:published_at).nil?

        now = Time.current
        live_at = @at || Publishing.pending(@record, now: now)&.live_at || now
        # A change with a time moves no address until that time, when nobody
        # can be refused any more. So it is asked now, of the site as it is
        # now: taken as if it were published at once, looked at, and rolled
        # back whatever the answer.
        lost = lost_if_published(now) if live_at > now
        next if lost.any?

        version = Version.take!(@record, live_at: live_at, by: actor_user, now: now)
        # Publishing never leaves a live record without an address
        # (`KeepsAddresses`): the copy is taken, the addresses have followed
        # it, and if one had to yield everything here is rolled back.
        lost = lost_addresses(@record, version.yields)
        raise ActiveRecord::Rollback if lost.any?

        record_event("#{prefix}.changes_published", subject: @record, coalesce: false,
          metadata: { "number" => version.number, "live_at" => version.live_at.iso8601, "scheduled" => version.live_at > now })
      end
      return failure(@record, lost) if lost.any?

      version ? success(@record) : failure(@record, [ NOT_PUBLISHED ])
    end

    private

    def lost_if_published(now)
      lost = []
      @record.class.transaction(requires_new: true) do
        lost = lost_addresses(@record, Version.take!(@record, by: actor_user, now: now).yields)
        raise ActiveRecord::Rollback
      end
      lost
    end

    def prefix = @record.is_a?(Page) ? "page" : "post"
  end
end
