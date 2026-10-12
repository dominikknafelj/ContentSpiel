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
      clash = false
      @record.class.transaction(requires_new: true) do
        # The page's row first, as every write that reads its blocks does.
        lock_owner(@record)
        next if @record.class.where(id: @record.id).pick(:published_at).nil?
        # Publishing never leaves a live record without an address: a post
        # whose tags, once published, put it under a list where another
        # record holds its address is refused here, before anything is
        # written (no copy, no address, no event), with the error its own
        # save gives for a taken address. Asked for a scheduled change too,
        # of the site as it is now; the sweep that brings that copy into
        # force cannot refuse, and yields (`PublicSite::Paths.held_by_others`).
        next clash = true if @record.is_a?(Post) && !address_free?

        now = Time.current
        version = Version.take!(@record, live_at: @at || Publishing.pending(@record, now: now)&.live_at || now, by: actor_user, now: now)
        record_event("#{prefix}.changes_published", subject: @record, coalesce: false,
          metadata: { "number" => version.number, "live_at" => version.live_at.iso8601, "scheduled" => version.live_at > now })
      end
      return failure(@record) if clash

      version ? success(@record) : failure(@record, [ NOT_PUBLISHED ])
    end

    private

    # Asked of the tags as stored now, not as this object loaded them.
    def address_free?
      @record.association(:tags).reset
      @record.address_free_as_typed?
    end

    def prefix = @record.is_a?(Page) ? "page" : "post"
  end
end
