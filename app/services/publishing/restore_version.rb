module Publishing
  # Returns a page's or a post's rows to the content of ANY of its published
  # versions (a row of `published_versions`, by its `number`), as
  # unpublished changes: never a publication (version history spec R3).
  # The site goes on showing the copy in force, and the record carries the
  # difference until someone publishes or discards it.
  #
  # WHAT COMES BACK, AND HOW, is `Publishing::ReturnTo`'s, as for a discard:
  # the content columns, the blocks reconciled by id in the version's order,
  # a post's tags by id, only what differs, through the save services. What
  # it cannot bring back (an image gone since, a tag deleted or renamed
  # since) stays different, is counted and said (`REMAINS`, `IMAGES_GONE`).
  #
  # WHAT IT LEAVES ALONE: every copy, the pending one included (a scheduled
  # change stays scheduled, R3: unlike a discard, nothing is withdrawn),
  # `published_at`, the slug and the tree. THE MARK follows what is true
  # after the return, as after a discard: set on a live or scheduled record
  # whose rows now differ from its newest copy, cleared when they are that
  # copy (the version restored was the newest), never set on a draft.
  #
  # THE DIALOG'S RECORD. A version never changes, but the rows can: the
  # confirmation showed what would change between them and the version as
  # the rows stood when it read them. So the press carries that row's
  # `updated_at` (`shown_updated_at:`), and a record saved since is refused
  # with `STALE` and nothing written (R12). A caller that showed nothing
  # (the console, a test) leaves it out and is not checked.
  #
  # RIGHTS are a discard's (`AccessControl::OwnerRule`: edit, and publish
  # once the record has a `published_at`), and bringing back a changed
  # image needs what choosing one needs (`Media::Choosing`, `media.upload`,
  # asked by the save service). That refusal comes from a step inside the
  # transaction, which takes its `access.denied` away with the rollback;
  # it is recorded again outside, once (`ReturnTo#refused_inside`, R7).
  #
  # One transaction, `lock_owner` first (the settings row, then the
  # record's row), then the block services, which take the page's row again
  # and then block rows (R11); a step that fails rolls all of it back.
  # Whether another tab holds part of the record is the controller's to
  # ask before this runs, as for every other write.
  class RestoreVersion < ApplicationService
    include ContentBlocks::Structure
    include ReturnTo

    NOT_ASKED = Object.new.freeze
    NOT_FOUND = "There is no such version".freeze
    STALE = "This %{kind} changed since you opened this. Look at the differences again.".freeze
    NOTHING = "Nothing to restore: the working version is already version %{number}.".freeze

    def initialize(record, number:, shown_updated_at: NOT_ASKED, actor: Current.actor)
      @record = record
      @number = number
      @shown_updated_at = shown_updated_at
      @actor = actor
    end

    def call
      # A state, not a right: no `access.denied` (`ApplicationService#switched_off_refusal`).
      dormant = switched_off_refusal(@record)
      return dormant if dormant

      refused = AccessControl::OwnerRule.refusal(@record) { |key| authorize!(key, @record) }
      return denied(refused, @record) if refused

      @left = []
      @refusal = nil
      done = @record.class.transaction(requires_new: true) do
        lock_owner(@record)
        @record.reload
        next refuse(format(STALE, kind: kind)) if stale?

        version = Version.of(@record).find_by(number: @number)
        next refuse(NOT_FOUND) if version.nil?
        next refuse(format(NOTHING, number: version.number)) if Changes.between(@record, from: version, to: :working).none?

        outcome = return_to!(version)
        @left = left_behind(outcome, Changes.between(@record, from: version, to: :working))
        # What differs is only what cannot be put back: nothing was written,
        # and no event says a restore happened.
        next false unless @wrote

        # THE MARK FOLLOWS WHAT IS TRUE NOW, read again under the lock, as
        # after a discard: the rows against the newest copy (`Changes.of`),
        # set when they differ and cleared when the version restored is
        # that copy. A draft carries no mark.
        if @record.published_at
          Changes.of(@record).none? ? Publishing.clear_changes(@record) : Publishing.note_change(@record)
        end

        record_event("#{kind}.version_restored", subject: @record, coalesce: false, snapshot: nil,
          metadata: { "number" => version.number, "images_missing" => outcome.images_missing, "tags_missing" => outcome.tags_missing }
            .reject { |key, count| key != "number" && count.zero? })
        @value = { number: version.number, images_missing: outcome.images_missing, tags_missing: outcome.tags_missing,
                   pending_at: Publishing.pending(@record)&.live_at }
        true
      end
      return success(@record, notice: @left.join(". ").presence, value: @value) if done
      return refused_inside if @denied

      # Past the refusals and a failed step, nothing was written although
      # the rows differed from the version: what differs is only what a
      # return cannot put back (an image gone since, counted even where the
      # row is already empty; a tag deleted or renamed since), so `@left`
      # names it and is never empty here.
      failure(@record, @errors.presence || [ @refusal ].compact.presence || @left)
    end

    private

    def kind = @record.is_a?(Page) ? "page" : "post"

    # A refusal decided under the lock: its sentence, and nothing written.
    def refuse(sentence)
      @refusal = sentence
      false
    end

    # The locked row's `updated_at` against the one the dialog read, to the
    # microsecond (what Postgres keeps).
    def stale?
      return false if @shown_updated_at.equal?(NOT_ASKED)

      @shown_updated_at&.floor(6) != @record.updated_at.floor(6)
    end
  end
end
