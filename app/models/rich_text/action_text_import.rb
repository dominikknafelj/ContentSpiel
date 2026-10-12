# `bin/rails rich_text:migrate_from_action_text` (design spec §5): converts
# every stored ActionText body into the record's per-locale JSON `body`,
# through `RichText::Document.from_html`.
#
# Run order on an existing install: `db:migrate` renames the JSON column to
# `body` and then stops at `DropActionText`, whose guard refuses to drop the
# ActionText tables while a body is still unconverted -- run this task, then
# `db:migrate` again. On a fresh install (or once ActionText is gone) the
# table doesn't exist and this prints "nothing to migrate".
#
# Contract:
# - **Idempotent.** A locale whose `body` already holds a non-blank
#   document is skipped, never overwritten -- whether an earlier run wrote
#   it or an editor did in CS Studio -- so re-running after a partial
#   failure only converts what's still missing. The flip side (accepted,
#   fix round 1 m2): until `DropActionText` has run, a locale an editor
#   *cleared* in CS Studio reads as blank, so a re-run refills it from its
#   old ActionText body.
# - **Blank results aren't written.** A body with content whose conversion
#   comes out blank -- its only content was an attachment that can't be
#   mapped (a remote file, a missing blob, a YoutubeEmbed whose row is
#   gone) or text inside dropped tags -- is counted and listed as "blank",
#   not "imported", and nothing is written, so a re-run lists it again
#   rather than silently rewriting it. `DropActionText`'s guard still
#   counts such a row as unconverted (it can't tell "unmappable" from "not
#   run yet"); once the listed rows are checked, migrate with
#   `FORCE_DROP_ACTION_TEXT=1`.
# - **Never aborts.** Each row is converted and written on its own, inside
#   its own transaction and rescue; a failure (orphaned row, unknown record
#   type, a language this site can't store, a document that fails
#   `#validate`) is recorded and printed, rolls back anything that row
#   created (a `Media::Asset`), and the run carries on.
# - **Reports.** Per-model counts, every unmapped fragment
#   (`RichText::HtmlImport`), every blank result, and every failure.
#
# Writes go straight to the column with `jsonb_set` (plus `updated_at`, and
# a `PublicSite.bump_version!`, so the content version -- and with it every
# cached page and rendered body -- moves on), bypassing model callbacks and
# validations
# (spec §5: "bypassing callbacks except path sync, which bodies don't
# affect"). The document is checked with `#validate` first instead, which is
# exactly the body validation `HasRichTextBody` would have run. Each written
# record's `media_usages` rows are then refreshed (`Media::UsageIndex`),
# which a save service would otherwise have done.
#
# ActionText rows come from `source` -- `SqlSource` by default, which reads
# `action_text_rich_texts` with plain SQL. Not `ActionText::RichText`: this
# has to keep loading after ActionText is removed from the app (same commit),
# and the tests inject rows through a stand-in with the same three methods,
# since the test database no longer has the table at all.
module RichText
  class ActionTextImport
    # The only models whose ActionText `body` this app ever declared
    # (`translates :body, backend: :action_text`), and so the only rows
    # with somewhere to go. Pages never had a body (spec §3.1).
    MODELS = %w[Post ContentBlock].freeze

    # Reads ActionText's storage with SQL alone (see the class comment).
    class SqlSource
      def available? = connection.table_exists?(:action_text_rich_texts)

      # Both tables are ActionText's and the old embed's own, with no model
      # left to ask: the statements are Arel over the bare table names.
      def each_row(&)
        texts = Arel::Table.new("action_text_rich_texts")
        rows = texts.project(texts[:record_type], texts[:record_id], texts[:name], texts[:locale], texts[:body])
          .order(texts[:record_type], texts[:record_id], texts[:locale])
        connection.select_all(rows).each(&) # sql: an Arel SELECT on a legacy table that has no model
      end

      def youtube_video_id(id)
        return nil unless connection.table_exists?(:youtube_embeds)

        embeds = Arel::Table.new("youtube_embeds")
        connection.select_value(embeds.project(embeds[:video_id]).where(embeds[:id].eq(id.to_i))) # sql: an Arel SELECT on a legacy table that has no model
      end

      private

      def connection = ActiveRecord::Base.connection
    end

    Stats = Struct.new(:imported, :blank, :skipped, :failed) do
      def to_s = "#{imported} imported, #{blank} blank, #{skipped} skipped, #{failed} failed"
    end

    def initialize(source: SqlSource.new, out: $stdout)
      @source = source
      @out = out
      @stats = Hash.new { |hash, key| hash[key] = Stats.new(0, 0, 0, 0) }
      @unmapped = []
      @blank = []
      @failures = []
    end

    def run
      unless @source.available?
        @out.puts "Nothing to migrate: there is no action_text_rich_texts table (ActionText has already been dropped)."
        return
      end

      @source.each_row { |row| import_row(row) }
      print_report
    end

    private

    # Raised inside the row's transaction to roll back whatever the import
    # already did (a `Media::Asset` created for an image) when the converted
    # document turns out invalid.
    class RowFailed < StandardError; end

    def import_row(row)
      type, id, locale = row["record_type"], row["record_id"], row["locale"].to_s
      label = "#{type}##{id} (#{locale})"
      stats = @stats[type]

      model = type.constantize if MODELS.include?(type)
      return fail_row(stats, label, "#{type} has no rich-text body") if model.nil? || row["name"] != "body"

      record = model.find_by(id: id)
      return fail_row(stats, label, "the record no longer exists") if record.nil?
      return stats.skipped += 1 if row["body"].to_s.strip.empty? || !record.body_document(locale: locale).blank?

      # One transaction per row (fix round 1, m3): converting can create
      # `Media::Asset`s, and a row that then fails must not leave them behind
      # as orphans no document references.
      outcome = ActiveRecord::Base.transaction do
        # A block's row is written below and then its page's
        # `translation_states` rows: the page's row is locked first, the one
        # order of locks for a write to a page's blocks (`ContentBlocks
        # ::Save#call`), so an import run while editors work cannot deadlock
        # against a section's delete or duplicate on the same page. The same
        # statement as `ContentBlocks::Structure#lock_owner`, written out:
        # this is a model, and takes nothing from a service.
        record.owner.class.where(id: record.owner_id).lock.pick(:id) if record.is_a?(ContentBlock) && record.owner
        document, unmapped = RichText::Document.from_html(row["body"], record: record, locale: locale, youtube_video_id: @source.method(:youtube_video_id))
        errors = document.validate
        raise RowFailed, "the converted document is invalid: #{errors.to_sentence}" if errors.any?

        @unmapped.concat(unmapped)
        next :blank if document.blank?

        write(model, id, locale, document)
        # The body was written past the services, so the owner's usage rows
        # are refreshed here, in the row's transaction (final fix wave, C1):
        # without a `rich_text` row an imported image reads as "Unused" and
        # can be deleted -- a rich-text reference has no FK to stop it.
        # Reloaded, since `UsageIndex` reads every locale's stored body.
        Media::UsageIndex.refresh(record.reload)
        # Same reason for the stored translation state: a translated body
        # can complete (or change) its owner's state in that language; a
        # block refreshes its owner.
        Translations::StateIndex.refresh(record)
        :imported
      end

      if outcome == :blank
        stats.blank += 1
        @blank << label
      else
        stats.imported += 1
      end
    rescue StandardError => error
      fail_row(stats, label, error.is_a?(RowFailed) ? error.message : "#{error.class}: #{error.message}")
    end

    def write(model, id, locale, document)
      model.where(id: id).update_all([
        "body = jsonb_set(COALESCE(body, '{}'::jsonb), ARRAY[?]::text[], ?::jsonb), updated_at = ?",
        locale, JSON.generate(document.to_h), Time.current
      ])
      # A body written around the callbacks: whether its post or its block's
      # page is live is not asked, the import is a one-off. Marked as changed
      # for what is published (`Publishing.note_change`, which asks): the body
      # is in a copy, and the owner's copy does not hold it until published.
      if model == ContentBlock
        ContentBlock.where(id: id).pluck(:owner_type, :owner_id).each { |type, owner_id| Publishing.note_change(type.constantize.where(id: owner_id)) }
      else
        Publishing.note_change(model.where(id: id))
      end
      PublicSite.bump_version!
    end

    def fail_row(stats, label, message)
      stats.failed += 1
      @failures << "#{label}: #{message}"
    end

    def print_report
      if @stats.empty?
        @out.puts "Nothing to migrate: action_text_rich_texts is empty."
        return
      end

      @stats.each { |type, stats| @out.puts "#{type}: #{stats}" }
      @out.puts "Unmapped fragments (#{@unmapped.size}):"
      @unmapped.each { |fragment| @out.puts "  #{fragment}" }
      @out.puts "Imported blank (#{@blank.size}): check these, then migrate with FORCE_DROP_ACTION_TEXT=1"
      @blank.each { |label| @out.puts "  #{label}" }
      @out.puts "Failures (#{@failures.size}):"
      @failures.each { |failure| @out.puts "  #{failure}" }
    end
  end
end
