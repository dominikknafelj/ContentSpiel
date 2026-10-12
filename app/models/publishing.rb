# Drafts of live content (drafts spec). Autosave writes the rows of a page or
# post; the public site shows a COPY taken when someone publishes
# (`Publishing::Version`, built and rebuilt by `Publishing::Snapshot`).
#
# WHAT IS PUBLISHED of a record is its current copy: the one with the greatest
# `live_at` not after now. A published record with no copy at all (a row
# written around the services: a console, a test) is served from its rows, as
# before this feature existed. A draft uses no copy, whatever copies it kept
# from an earlier publication.
#
# NOT IN A COPY, and immediate as before: the slug, the place in the tree,
# `published_at`, the trash, a post's content type.
#
# `Admin::Publishing` is never defined: it would shadow this module for every
# bare `Publishing::` inside `module Admin`.
module Publishing
  # EVERY COLUMN OF THE THREE TABLES HAS A PLACE, in exactly one of three
  # lists, and `test/models/publishing_test.rb` reads the real columns from
  # the schema and fails for a column in none of them or in two: adding a
  # column to `pages`, `posts` or `content_blocks` means deciding here
  # whether the public sees it from the copy or from the rows.
  #
  # IN THE COPY. Includes `translation_sources` and
  # `translation_original_changed_at` of all three models, although nothing
  # reads them back: nothing public draws them, the overview does not
  # compare them (`Publishable::BOOKKEEPING`), and "Discard changes" does NOT
  # copy them back (`Publishing::DiscardChanges`: translation bookkeeping is
  # what the save services leave when the text is written back). They are
  # kept as a record of what the marks were when the copy was taken.
  CONTENT = {
    "Page" => %w[title subtitle meta_title meta_description hero_alt hero_media_asset_id page_type
                 translation_sources translation_original_changed_at],
    "Post" => %w[title excerpt body metadata translated_metadata translation_sources translation_original_changed_at],
    # A block's copy is the whole row (`Snapshot.blocks_of`).
    "ContentBlock" => %w[id alt block_type caption created_at owner_id owner_type position settings translated_settings
                         updated_at body media_asset_id translation_sources translation_original_changed_at
                         section_id section_column]
  }.freeze

  # LEFT ON THE ROWS ON PURPOSE: immediate as before, each with its reason.
  ROWS = {
    "Page" => {
      "slug" => "an address is immediate (drafts spec §3)",
      "parent_id" => "the place in the tree is immediate",
      "position" => "the place in the tree is immediate",
      "published_at" => "publishing and scheduling are immediate",
      "trashed_at" => "the trash is immediate",
      "trashed_by_id" => "the trash is immediate",
      "trash_root_id" => "the trash is immediate",
      "settings_changed_at" => "editor state: when the settings last changed; no public reader",
      "unpublished_changes_at" => "editor state: the mark that the rows moved on from the copy; no public reader"
    },
    "Post" => {
      "slug" => "an address is immediate",
      "content_type" => "a post's type is immediate",
      "published_at" => "publishing and scheduling are immediate",
      "trashed_at" => "the trash is immediate",
      "trashed_by_id" => "the trash is immediate",
      "author_id" => "no public component draws the author",
      "unpublished_changes_at" => "editor state: the mark that the rows moved on from the copy; no public reader"
    },
    "ContentBlock" => {}
  }.freeze

  # NEVER STORED: the record's identity and bookkeeping; a rebuilt record has
  # the row's (`updated_at` dates a record with no copy in the sitemap; a record with one is dated by its copy, and the ETag names the copy's id).
  NEVER_STORED = {
    "Page" => { "id" => "the record itself", "created_at" => "bookkeeping", "updated_at" => "bookkeeping" },
    "Post" => { "id" => "the record itself", "created_at" => "bookkeeping", "updated_at" => "bookkeeping" },
    "ContentBlock" => {}
  }.freeze

  module_function

  # What the public sees of `record`, with a page's blocks: a read-only
  # record rebuilt from its current copy, or `record` itself when it is a
  # draft or has no copy (see the head of this file).
  def published(record, now: Time.current) = published_all([ record ], now: now, with_blocks: true).first

  # The same for several records at once, in the order given, in one query
  # per record type. Without blocks unless asked: a menu, a list of subpages
  # and a post list read titles and excerpts, and a page's blocks are most
  # of a copy's weight. A view rebuilt without blocks must not be asked for
  # them: its `content_blocks` would query the rows.
  def published_all(records, now: Time.current, with_blocks: false)
    records = records.to_a
    using = records.select { |record| record.published_at.present? }
    return records if using.empty?

    columns = with_blocks ? Version.column_names : Version.column_names - [ "blocks" ]
    copies = using.group_by { |record| record.class.polymorphic_name }.values.reduce({}) do |all, group|
      all.merge(Version.current_for(group, now: now, columns: columns))
    end

    records.map do |record|
      version = copies[[ record.class.polymorphic_name, record.id ]] if record.published_at.present?
      version ? Snapshot.rebuild(version, record, with_blocks: with_blocks) : record
    end
  end

  def content_columns(record)
    CONTENT.fetch(record.is_a?(Class) ? record.polymorphic_name : record.class.polymorphic_name)
  end

  # The copy the public sees now (or at `now`), or nil: one statement, served
  # by the `(record_type, record_id, live_at)` index. `id` breaks a tie of
  # `live_at`; ids and times rise together (`Version`).
  def current(record, now: Time.current) = Version.of(record).in_force(now).order(live_at: :desc, id: :desc).first

  # The newest copy, pending or current: what the overview compares the rows
  # with. (A discard returns to the copy IN FORCE, `current`, and withdraws a
  # pending one.)
  def baseline(record) = Version.of(record).order(number: :desc).first

  # The copy waiting for its time, or nil. There is at most one.
  def pending(record, now: Time.current) = Version.of(record).pending(now).first

  # Whether the public sees a copy of this record now: one is in force. A
  # record with only a pending copy (a change published with a time, on a
  # record that had no copy) is still shown from its rows until that time.
  def in_force?(record, now: Time.current) = Version.of(record).in_force(now).exists?

  # THE MARK (`unpublished_changes_at`, drafts spec §4.4) says THAT the rows of
  # a published or scheduled record have moved on from what is published;
  # `Publishing::Changes` says how. A save and a touch set it
  # (`Publishable`); these two are for a write around the callbacks
  # (`update_columns`, `touch_all`, `insert_all` on a join table) and for the
  # services that take a copy or find there is nothing to take. Neither moves
  # the public content version: nothing public reads the mark.
  #
  # Marks the published and scheduled records of `records` (a record or a
  # relation); a draft has no copy to differ from.
  def note_change(records, now: Time.current)
    relation = records.is_a?(ActiveRecord::Relation) ? records : records.class.where(id: records.id)
    relation.where.not(published_at: nil).update_all(unpublished_changes_at: now) # version: none (a mark CS Studio reads; no page shows it)
  end

  # The rows and the newest copy are the same now (a copy was taken, or the
  # difference was found to be nothing): nothing is waiting. Also on the
  # object in memory, as a read, so the next screen drawn from it is true.
  def clear_changes(record)
    record.class.where(id: record.id).update_all(unpublished_changes_at: nil) # version: none (a mark CS Studio reads; no page shows it)
    record.unpublished_changes_at = nil
    record.clear_attribute_changes([ :unpublished_changes_at ])
  end

  # THE ONE CHECK THAT REFUSES A SAVE OR A PUBLISH FOR AN ADDRESS, after the
  # slug's validation (`HasPublicPaths#public_paths_are_available`), which
  # refuses before anything is written wherever it can see the clash. What it
  # cannot see: a tag the very save made, and the tags a publish makes
  # public. So this is the record's own refresh, in the caller's
  # transaction, and it raises `AddressTaken`, which rolls that transaction
  # back, when THE RECORD ITSELF had to yield: it would be on the site, or
  # in the preview, with no address. `shown:` (a record that is on the site
  # already, whose changes are being published): only an address it HAD
  # counts, so a post that stands without one goes on publishing its text.
  #
  # ANOTHER record that has to yield never refuses anything: it yields, as
  # for any other write (`PublicSite::Paths.refresh` logs and reports it).
  #
  # For `take!` of `Version` (every publish) and `Posts::Save` (a draft's tags).
  def keep_address!(record, now: Time.current, shown: false)
    touched = { (record.is_a?(Page) ? :pages : :posts) => [ record ] }
    own = PublicSite::Paths.refresh(**touched, now: now).select { |change| change.record == record && (change.row_id || !shown) }
    raise AddressTaken.new(own) if own.any?
  end
end
