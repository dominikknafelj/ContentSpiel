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
  # `published_at`, the slug and the tree. THE MARK is what the save
  # services leave: set on a live or scheduled record when they write
  # content, never on a draft, and never cleared here.
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
  # it is recorded again here, outside, once (R7).
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

        record_event("#{kind}.version_restored", subject: @record, coalesce: false, snapshot: nil,
          metadata: { "number" => version.number, "images_missing" => outcome.images_missing, "tags_missing" => outcome.tags_missing }
            .reject { |key, count| key != "number" && count.zero? })
        @value = { number: version.number, images_missing: outcome.images_missing, tags_missing: outcome.tags_missing,
                   pending_at: Publishing.pending(@record)&.live_at }
        true
      end
      return success(@record, notice: @left.join(". ").presence, value: @value) if done
      return refused_inside if @denied

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

    # Which permission refused the step: the owner's keys were all held a
    # moment ago and are asked once more in case that changed; otherwise
    # what a step refuses is the choice of an image (`Media::Choosing`).
    def refused_inside
      denied(AccessControl::OwnerRule.refusal(@record) { |key| authorize!(key, @record) } || "media.upload", @record)
    end
  end
end
