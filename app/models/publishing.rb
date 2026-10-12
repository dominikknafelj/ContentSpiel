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
  # `translation_original_changed_at` of all three models: nothing public
  # draws them (a copy is never public as such), but "Discard changes" must
  # put back a translated field together with the marks that say whether the
  # translation is current, or the marks would be wrong afterwards.
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
      "settings_changed_at" => "editor state: when the settings last changed; no public reader"
    },
    "Post" => {
      "slug" => "an address is immediate",
      "content_type" => "a post's type is immediate",
      "published_at" => "publishing and scheduling are immediate",
      "trashed_at" => "the trash is immediate",
      "trashed_by_id" => "the trash is immediate",
      "author_id" => "no public component draws the author"
    },
    "ContentBlock" => {}
  }.freeze

  # NEVER STORED: the record's identity and bookkeeping; a rebuilt record has
  # the row's (`updated_at` feeds the sitemap (the ETag names the copy's id for a record that has one), which read rows).
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

  # The current copy of each of these records in ONE statement:
  # `{ [record_type, record_id] => Version }`, a record with none left out.
  def current_for(records, now: Time.current) = Version.current_for(records, now: now)

  # The newest copy, pending or current: what "Discard changes" returns to
  # and what the overview compares the rows with.
  def baseline(record) = Version.of(record).order(number: :desc).first

  # The copy waiting for its time, or nil. There is at most one.
  def pending(record, now: Time.current) = Version.of(record).pending(now).first

  def copied?(record) = Version.of(record).exists?

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
