module Publishing
  # Returns the rows of a published or scheduled page or post to WHAT IS IN
  # FORCE (drafts spec §4.3: "the current copy"), through the services every
  # other write goes through, so that each rule they hold (validation, media,
  # translation tracking, derived rows, the audit log, live refresh) holds
  # for a discard.
  #
  # THE COPY IN FORCE, NOT THE NEWEST. A change that is scheduled and has not
  # come into force is unpublished too: the discard withdraws it
  # (`Version.withdraw_pending!`) and the rows go back to what the site
  # shows now. A record whose only copy is pending is shown from its rows and
  # has nothing to return to.
  #
  # WHAT COMES BACK, AND HOW, is `Publishing::ReturnTo`'s: the content
  # columns, the blocks reconciled by id in its order, only what differs,
  # through the save services. What it cannot bring back stays different:
  # a tag renamed or deleted since (`REMAINS`; a merged one leaves nothing
  # to say, since a merge rewrites the copies too) and an image deleted or
  # moved to the trash since, left empty (`IMAGES_GONE`). The discard
  # succeeds, says so (the result's `notice`), and the mark STAYS: the
  # difference is visible in the overview and is published, or left, by a
  # person.
  #
  # One transaction, the record's row lock first (the lock order of every
  # block write: each block service driven here takes the page's row again,
  # which this transaction already holds, and then block rows); a step that
  # fails rolls all of it back. Nothing public moves: the site shows the
  # copy, before and after. Whether another tab holds part of the record is
  # asked by the controller before this runs
  # (`Admin::EditingClaims#refuse_discard_under_hold`), as for every other
  # write: a call with no tab (the console) is not refused.
  class DiscardChanges < ApplicationService
    include ContentBlocks::Structure
    include ReturnTo
    include ShownSchedule

    NOTHING = "There is nothing to discard".freeze
    # What a discard cannot put back: a tag is a reference, not content of
    # the record, and one that was renamed or deleted since the copy was
    # taken stays as it is now (`ReturnTo`, TAGS). Not a merged one: a merge
    # rewrites the copies too and leaves nothing to say.
    REMAINS = "A tag was renamed or deleted since this was published: that difference stays, as unpublished changes".freeze
    # An image is a reference too: one deleted or moved to the trash since
    # the copy was taken is left empty, never pointed at (`ReturnTo`, IMAGES).
    IMAGES_GONE = "An image was deleted or moved to the trash since this was published: it is left empty, as unpublished changes".freeze

    def initialize(record, shown_pending: NOT_ASKED, actor: Current.actor)
      @record = record
      @shown_pending = shown_pending
      @actor = actor
    end

    def call
      # A state, not a right: no `access.denied` (`ApplicationService#switched_off_refusal`).
      dormant = switched_off_refusal(@record)
      return dormant if dormant

      refused = AccessControl::OwnerRule.refusal(@record) { |key| authorize!(key, @record) }
      return denied(refused, @record) if refused

      @wrote = @moved = false
      @left = []
      done = @record.class.transaction(requires_new: true) do
        lock_owner(@record)
        @record.reload
        now = Time.current
        version = @record.published_at.nil? ? nil : Publishing.current(@record, now: now)
        next false if version.nil?
        # A scheduled change the dialog did not mention would go with it (`ShownSchedule`).
        next @moved = true if schedule_moved?(@record, now)

        # Nothing differs and nothing is scheduled: a mark left by typing
        # and typing back is cleared, and no event says a discard happened.
        if Changes.new(@record, version).none? && Publishing.pending(@record, now: now).nil?
          Publishing.clear_changes(@record)
          next false
        end

        outcome = return_to!(version)
        withdrawn = Version.withdraw_pending!(@record, now: now).last
        Media::UsageIndex.refresh_published(@record, now: now) if withdrawn
        # THE MARK FOLLOWS WHAT IS TRUE NOW, read again under the lock: gone
        # when the rows are the copy, kept when something could not be put
        # back (`REMAINS`, `IMAGES_GONE`), so that difference can still be
        # seen, published or left, and never goes public unseen with a later
        # publish.
        changes = Changes.new(@record, version)
        @left = left_behind(outcome, changes)
        changes.none? ? Publishing.clear_changes(@record) : Publishing.note_change(@record, now: now)
        # Nothing was written and nothing withdrawn: what differs is only
        # what cannot be put back. No event says a discard happened.
        next false unless @wrote || withdrawn

        record_event("#{@record.is_a?(Page) ? "page" : "post"}.changes_discarded", subject: @record, coalesce: false,
          metadata: { "number" => version.number, "withdrawn_number" => withdrawn }.compact)
        true
      end
      return failure(@record, [ MOVED ]) if @moved
      return success(@record, notice: @left.join(". ").presence) if done

      failure(@record, @errors.presence || @left.presence || [ NOTHING ])
    end

    private

    # The sentences for what stays different after the return. With no image
    # missing every difference left is a tag's (the return puts back all
    # else); with one, a tag's sentence joins only where a tag still
    # differs: the post's tags, or a block whose settings or listed tag do
    # (an image left empty differs in `media_asset_id` alone, and a block
    # made again without its image stands as one removed and one added).
    def left_behind(outcome, changes)
      return [] if changes.none?
      return [ REMAINS ] if outcome.images_missing.zero?

      tags = changes.fields.include?("tags") || changes.blocks.any? do |entry|
        was, now = changes.sides_of(entry)
        was && now && was.values_at("settings", "listed_tag_id") != now.values_at("settings", "listed_tag_id")
      end
      [ IMAGES_GONE, (REMAINS if tags) ].compact
    end
  end
end
