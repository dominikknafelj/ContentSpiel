module Tags
  # Merges one tag into another (round 3 design pass, D20; spec §5.6): every
  # post that carries `source` gets `into` instead, the listing blocks that
  # filtered by `source` now filter by `into`, and `source` is deleted. No undo,
  # one `tag.merged` event on the target.
  #
  # Everything is one transaction, so a failure part-way leaves nothing
  # half-merged; only the resync of derived URLs runs after it commits (as in
  # `Tags::Rename`/`Destroy`), because it reads committed rows.
  #
  # What is deliberately NOT done, and why:
  # - No per-post event. A merge is one decision about tags; the posts' own
  #   history would otherwise gain one "updated" row each, saying nothing the
  #   `tag.merged` event (and its `posts` count) doesn't. The carriers are only
  #   touched, so an open form of theirs goes stale (below).
  # - No `Media::UsageIndex` or `Translations::StateIndex` refresh: a tag is in
  #   neither -- usage rows record images, translation states record
  #   translated fields, and neither the tag name (untranslated) nor a block's
  #   `tag` setting (an untranslated `:string` field) is one.
  # - No de-duplication of blocks: a page that had a block for `source` and one
  #   for `into` now has two blocks that list the same posts. That is what the
  #   editor built; merging tags is not an instruction to edit the page.
  class Merge < ApplicationService
    include Tags::Listings

    # The three refusals, read from `admin.tags.merge` in
    # `config/locales/admin/tags.en.yml` at the moment they are asked for, not at
    # load, so a locale switched afterwards is the one they come in. Plain class
    # methods (`Tags::Merge.gone`, `result.errors == [ Tags::Merge.missing_tag ]`):
    # a caller compares with them or shows them, and a missing key raises
    # `I18n::MissingTranslationData` rather than render a "translation missing"
    # sentence into a toast.
    def self.same_tag = message("same_tag")
    def self.missing_tag = message("missing_tag")
    def self.gone = message("gone")

    def self.message(key) = I18n.t("admin.tags.merge.#{key}", raise: true)
    private_class_method :message

    def initialize(source, into:, actor: Current.actor)
      @source = source
      @into = into
      @actor = actor
    end

    # Needs `tags.manage`, like the other tag services -- tags are shared by
    # every post, so there is no record scope to check. The authorisation comes
    # first so a caller without the right learns nothing about the arguments.
    def call
      return denied("tags.manage", @source) unless authorize!("tags.manage", @source)
      # Not a tag at all -- nil from a name that matched nothing, or whatever a
      # caller outside CS Studio handed over -- is "none chosen", a plain failure.
      return failure(@source, [ self.class.missing_tag ]) unless @into.is_a?(Tag)
      return failure(@source, [ self.class.same_tag ]) if @into.id == @source.id

      problem = nil
      content_types = []
      merged = Tag.transaction do
        # Both rows locked, in id order, so two merges running the other way round
        # (A into B, B into A) queue up instead of deadlocking, and a tag deleted
        # in another tab since this one loaded it is a plain failure here rather
        # than a foreign-key exception out of the insert below. The locked rows
        # are the truth from here on (the name may have changed since).
        locked = Tag.where(id: [ @source.id, @into.id ]).order(:id).lock.index_by(&:id)
        source, into = locked[@source.id], locked[@into.id]
        if source.nil? || into.nil?
          problem = self.class.gone
          raise ActiveRecord::Rollback
        end

        # Kept and trashed posts alike: a trashed post that is restored later must
        # come back carrying `into`, not a tag that no longer exists. This is
        # also the "posts that had the tag" number the event records.
        carrier_ids = source.post_tags.pluck(:post_id)

        # Read before anything changes: which listings are affected is decided by
        # the blocks as they stand now (a block naming either tag, whichever
        # content types they list).
        content_types = affected_content_types(source.name, into.name, tag_ids: [ source.id, into.id ])
        blocks = listing_blocks_naming(source.name)

        give_target_to_carriers(into, carrier_ids)
        touch_carrying_posts(source)
        repoint_blocks(blocks, source, into)
        # The published copies too, after the page locks above: a merge is
        # immediate everywhere, as a slug is. The copies reference the tag by
        # id and `source`'s is about to stop existing, so the lists and the
        # addresses the public has stay exactly what they are
        # (`Publishing::Version.repoint_tag!`).
        Publishing::Version.repoint_tag!(from: source, to: into)
        PostTag.where(tag_id: source.id).delete_all
        source.destroy!
        # Join rows and block settings were written around the callbacks
        # (`insert_all`, `delete_all`, `update_columns`, `touch_all`), so no
        # post's or page's `after_commit` speaks for them: the merge moves
        # the public content version itself, deferred to the commit.
        PublicSite.bump_version!

        record_event("tag.merged", subject: into, metadata: { "merged" => source.name, "posts" => carrier_ids.size })
        into
      end

      return failure(@source, [ problem ]) if problem

      # Join rows were written without callbacks (`insert_all`/`delete_all`), so
      # `PostTag#sync_post_paths` didn't run per post -- and needn't: a post's
      # canonical page depends on its tags only through listing blocks that
      # filter by tag, and every block that names either tag is in
      # `content_types`, which this re-derives from scratch.
      content_types.each { |content_type| PublicSite::Paths.sync_posts(content_type) }
      success(merged)
    end

    private

    # One statement that cannot race into a duplicate: a post that already has
    # `into` hits the unique (post_id, tag_id) index and is skipped by the
    # database, not by a check that another writer could slip past.
    def give_target_to_carriers(into, carrier_ids)
      return if carrier_ids.empty?

      PostTag.insert_all(carrier_ids.map { |post_id| { post_id: post_id, tag_id: into.id } },
        unique_by: :index_post_tags_on_post_id_and_tag_id)
    end

    # Points every matched block at `into`'s name, leaving its other settings be.
    # `update_columns`, not a save: the save callbacks would resync the block's
    # content type once per block (this resyncs once, after the commit) and run
    # the settings validations on a block that is valid as stored. Both the
    # block and its owning page are touched: a block card or page form that was
    # open resends the OLD tag name on its next autosave, and a moved
    # `updated_at` makes that save a 409 ("Changed elsewhere") instead of
    # quietly undoing the merge.
    #
    # `blocks` were read at the start of the merge, to know which listings it
    # affects. Their settings are NOT written back from that read: the rows are
    # loaded again here under a row lock (in id order, like the tags), and the
    # tag is merged into the settings as they are stored now -- so a limit or a
    # content type another editor saved in between survives, and a block that
    # has been pointed at some other tag meanwhile is left alone (the same
    # match as `Listings#listing_blocks_naming`, asked again of the fresh row).
    # The lock holds until the commit, so a block save arriving after it sees
    # the new tag and the moved `updated_at`.
    #
    # The blocks' pages are locked BEFORE the blocks, in id order. The order
    # of locks for a page's blocks is the page's row, then block rows
    # (`ContentBlocks::Save#call`): a block save or delete holds its page and
    # waits for the block. This method used to take the block rows and only
    # then the pages (the `touch_all` at the end), so a merge and a save of
    # one of these listing blocks could each hold what the other waited for,
    # until Postgres ended one with `ActiveRecord::Deadlocked`. Id order, so
    # two merges, or a merge and a branch purge (`Trash::Purge`), take these
    # rows the same way round. A known gap is left on the purge's side: a
    # page's destroy renumbers its siblings (closure_tree's
    # `_ct_reorder_siblings`), page rows outside the purge's id-ordered
    # lock, so a merge holding such a sibling and that purge can still
    # deadlock.
    #
    # Which pages: the owners of `blocks`, the read made without any lock.
    # That read can be behind, but not in a way that leaves a block locked
    # without its page: the fresh rows below are asked for by these same ids,
    # and a block never changes its owner, so every row locked there belongs
    # to a page locked here. A block deleted since is simply not found; one
    # pointed elsewhere since is locked, its page too, and left alone -- a
    # page locked and not touched costs nothing. (A block that started
    # naming the source after the read isn't in `blocks` at all, with or
    # without these locks.)
    def repoint_blocks(blocks, source, into)
      return if blocks.empty?

      now = Time.current
      Page.where(id: blocks.select { |block| block.owner_type == "Page" }.map(&:owner_id)).order(:id).lock.pluck(:id) # i18n-ok: a class name compared with owner_type
      fresh = ContentBlock.where(id: blocks.map(&:id)).order(:id).lock.select { |block| block_names_tag?(block, source.name) }
      fresh.each { |block| block.update_columns(settings: block.settings.merge("tag" => into.name), updated_at: now) }
      Page.where(id: fresh.select { |block| block.owner_type == "Page" }.map(&:owner_id)).touch_all # i18n-ok: a class name compared with owner_type
    end
  end
end
