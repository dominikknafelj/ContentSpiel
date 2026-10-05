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
  # - No `PublicSite.content_version` call: it is derived from the newest
  #   `updated_at` of posts, blocks, pages and the paths table, all of which
  #   this moves when a listing could change (the render cache is keyed on it).
  # - No de-duplication of blocks: a page that had a block for `source` and one
  #   for `into` now has two blocks that list the same posts. That is what the
  #   editor built; merging tags is not an instruction to edit the page.
  class Merge < ApplicationService
    include Tags::Listings

    # The three refusals, read from `admin.tags.merge` in
    # `config/locales/admin/tags.en.yml` at the moment they are asked for, not at
    # load, so a locale switched afterwards is the one they come in. They are
    # constants to every caller (`Tags::Merge::GONE`, `result.errors ==
    # [ Tags::Merge::MISSING_TAG ]`) but resolved here by `const_missing`, which
    # never defines the constant, so the lookup runs on every reference.
    MESSAGE_KEYS = { SAME_TAG: "same_tag", MISSING_TAG: "missing_tag", GONE: "gone" }.freeze

    def self.const_missing(name)
      key = MESSAGE_KEYS[name]
      key ? I18n.t("admin.tags.merge.#{key}", raise: true) : super
    end

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
      return failure(@source, [ MISSING_TAG ]) unless @into.is_a?(Tag)
      return failure(@source, [ SAME_TAG ]) if @into.id == @source.id

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
          problem = GONE
          raise ActiveRecord::Rollback
        end

        # Kept and trashed posts alike: a trashed post that is restored later must
        # come back carrying `into`, not a tag that no longer exists. This is
        # also the "posts that had the tag" number the event records.
        carrier_ids = source.post_tags.pluck(:post_id)

        # Read before anything changes: which listings are affected is decided by
        # the blocks as they stand now (a block naming either tag, whichever
        # content types they list).
        content_types = affected_content_types(source.name, into.name)
        blocks = listing_blocks_naming(source.name)

        give_target_to_carriers(into, carrier_ids)
        touch_carrying_posts(source)
        repoint_blocks(blocks, source, into)
        PostTag.where(tag_id: source.id).delete_all
        source.destroy!

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
    def repoint_blocks(blocks, source, into)
      return if blocks.empty?

      now = Time.current
      fresh = ContentBlock.where(id: blocks.map(&:id)).order(:id).lock.select { |block| block_names_tag?(block, source.name) }
      fresh.each { |block| block.update_columns(settings: block.settings.merge("tag" => into.name), updated_at: now) }
      Page.where(id: fresh.select { |block| block.owner_type == "Page" }.map(&:owner_id)).touch_all # i18n-ok: a class name compared with owner_type
    end
  end
end
