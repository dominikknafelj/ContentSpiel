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
#   failure only converts what's still missing.
# - **Never aborts.** Each row is converted and written on its own, inside
#   its own rescue; a failure (orphaned row, unknown record type, a
#   language this site can't store, a document that fails `#validate`) is
#   recorded and printed, and the run carries on.
# - **Reports.** Per-model counts, every unmapped fragment
#   (`RichText::HtmlImport`), and every failure.
#
# Writes go straight to the column with `jsonb_set` (plus `updated_at`, so
# `PublicSite.content_version` -- and with it every cached page and
# rendered body -- moves on), bypassing model callbacks and validations
# (spec §5: "bypassing callbacks except path sync, which bodies don't
# affect"). The document is checked with `#validate` first instead, which is
# exactly the body validation `HasRichTextBody` would have run.
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

      def each_row(&)
        connection.select_all("SELECT record_type, record_id, name, locale, body FROM action_text_rich_texts ORDER BY record_type, record_id, locale").each(&)
      end

      def youtube_video_id(id)
        return nil unless connection.table_exists?(:youtube_embeds)

        connection.select_value(ActiveRecord::Base.sanitize_sql([ "SELECT video_id FROM youtube_embeds WHERE id = ?", id.to_i ]))
      end

      private

      def connection = ActiveRecord::Base.connection
    end

    Stats = Struct.new(:imported, :skipped, :failed) do
      def to_s = "#{imported} imported, #{skipped} skipped, #{failed} failed"
    end

    def initialize(source: SqlSource.new, out: $stdout)
      @source = source
      @out = out
      @stats = Hash.new { |hash, key| hash[key] = Stats.new(0, 0, 0) }
      @unmapped = []
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

    def import_row(row)
      type, id, locale = row["record_type"], row["record_id"], row["locale"].to_s
      label = "#{type}##{id} (#{locale})"
      stats = @stats[type]

      model = type.constantize if MODELS.include?(type)
      return fail_row(stats, label, "#{type} has no rich-text body") if model.nil? || row["name"] != "body"

      record = model.find_by(id: id)
      return fail_row(stats, label, "the record no longer exists") if record.nil?
      return stats.skipped += 1 if row["body"].to_s.strip.empty? || !record.body_document(locale: locale).blank?

      document, unmapped = RichText::Document.from_html(row["body"], record: record, locale: locale, youtube_video_id: @source.method(:youtube_video_id))
      errors = document.validate
      return fail_row(stats, label, "the converted document is invalid: #{errors.to_sentence}") if errors.any?

      write(model, id, locale, document)
      @unmapped.concat(unmapped)
      stats.imported += 1
    rescue StandardError => error
      fail_row(stats, label, "#{error.class}: #{error.message}")
    end

    def write(model, id, locale, document)
      model.where(id: id).update_all([
        "body = jsonb_set(COALESCE(body, '{}'::jsonb), ARRAY[?]::text[], ?::jsonb), updated_at = ?",
        locale, JSON.generate(document.to_h), Time.current
      ])
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
      @out.puts "Failures (#{@failures.size}):"
      @failures.each { |failure| @out.puts "  #{failure}" }
    end
  end
end
