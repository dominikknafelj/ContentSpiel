module Admin
  module HistoryScreen
    # The restore dialog (the StudioHistory card, "The restore dialog";
    # version history spec R3, R6 to R9, R16): "Restore version 5?", the
    # sentence that the working version becomes it and nothing is published,
    # the overview of what changes in the working version
    # (`Admin::Ui::ChangesOverviewComponent`, `detail: :names`, of `changes`:
    # the working version against the chosen one), then the lines of what
    # does not come back as it was, and a schedule that stays.
    #
    # DRAWN WITH THE SCREEN, and read with it: the History screen has no
    # autosave and no write queue a save could be waiting in, so what the
    # GET read is what the press acts on, and the form carries the record's
    # `updated_at` as read (`shown_updated_at`), which
    # `Publishing::RestoreVersion` checks under its lock: a colleague's save
    # in between refuses the press (R12). The form is `_top` behind
    # `admin--saving--queue-hold`, as the editor's discard form is, and it
    # stands outside the comparison's GET form (no form inside a form).
    #
    # THE CONDITIONAL LINES, one warn notice with no role of its own (the card:
    # the overview says what changes; these say what a person might not
    # expect): blocks that come back (the version's blocks the rows lost, made
    # again under new ids, without the notes the removed block had), blocks
    # that go and carry open notes (deleted with them, R6), the version's
    # library images that are gone or in the trash (left empty, R7) and the
    # tags it names that no longer exist (left off, R8). Counted as
    # `Publishing::ReturnTo` counts them when the restore runs.
    #
    # A version the same as the working version has nothing to restore: the
    # sentence says so, and Close is the only action.
    class RestoreDialogComponent < Admin::AdminComponent
      ID = "history-restore".freeze

      # `shown_at`: when the version goes or went live for a visitor
      # (`Publishing::History#shown_at`), which the sentence names.
      def initialize(record:, version:, shown_at:, changes:, locale:, url_options: {})
        @record = record
        @version = version
        @shown_at = shown_at
        @changes = changes
        @locale = locale.to_s
        @url_options = url_options
      end

      attr_reader :record, :version, :changes, :locale

      def id = ID

      def form_id = "#{ID}-form"

      def number = version.number

      def nothing? = changes.none?

      def kind = record.is_a?(::Page) ? "page" : "post"

      def url = helpers.admin_publishing_restore_path(kind: kind, id: record.id, **@url_options)

      def queue_hold = { turbo_frame: "_top", controller: "admin--saving--queue-hold", action: "submit->admin--saving--queue-hold#submit" }

      # What the dialog read, to the microsecond Postgres keeps.
      def shown_updated_at = record.updated_at.iso8601(6)

      # "Pricing’s working version becomes version 5 as it went live on
      # 3 Nov 2026. Nothing is published: the site keeps showing version 7
      # until you publish the changes." A copy still waiting for its time
      # goes live; a record the site does not show keeps showing nothing.
      def sentence
        becomes = t(@shown_at.future? ? ".becomes.goes" : ".becomes.went", title: title, number: number, date: date(@shown_at))
        on_site = ::Publishing::State.of(record).live? && ::Publishing.current(record)
        t(".sentence", becomes: becomes, site: on_site ? t(".site.shown", number: on_site.number) : t(".site.none"))
      end

      def warnings
        [
          (t(".back", count: back) if back.positive?),
          going_line,
          (t(".images", count: images_missing) if images_missing.positive?),
          (t(".tags", count: tags_missing) if tags_missing.positive?)
        ].compact
      end

      # The change that waits for its time stays scheduled (R3).
      def schedule_line
        pending = ::Publishing.pending(record) or return
        t(".schedule", time: I18n.l(pending.live_at.in_time_zone(zone), format: :"admin.datetime"))
      end

      private

      def zone = Current.site.effective_time_zone

      def title = ::Locales.read(record, :title, locale: locale).presence || t(".untitled")

      def date(time) = I18n.l(time.in_time_zone(zone).to_date, format: :"admin.short_with_year")

      def entries(kind) = changes.blocks.select { |entry| entry.kind == kind }

      # Every block the version has and the rows do not is made again: the
      # overview pairs a block an earlier return made again with the
      # version's (`Changes.stand_ins`), so an added entry is one that comes
      # back under a new id.
      def back = entries(:added).size

      # The open notes on the blocks that go, read once, as their reader may
      # see them (`Notes.readable_threads`).
      def going_line
        ids = entries(:removed).map { |entry| entry.block.id }
        return if ids.empty?

        counts = ::Notes.readable_threads(Current.actor).unresolved.where(subject_type: "ContentBlock", subject_id: ids).group(:subject_id).count
        return if counts.empty?

        notes = counts.values.sum
        counts.size == 1 ? t(".going_one", count: notes) : t(".going_many", blocks: counts.size, count: notes)
      end

      # The version's library images (the hero and each image block's) that
      # are deleted or in the trash, each once: one statement.
      def images_missing
        @images_missing ||= begin
          ids = [ version.snapshot.fetch("fields", {})["hero_media_asset_id"], *version.blocks.map { |block| block["media_asset_id"] } ].compact.uniq
          ids.empty? ? 0 : ids.size - ::Media::Asset.kept.where(id: ids).count
        end
      end

      # The tags the version names that no longer exist: a post's (each
      # once) and each list block's filter, as the restore counts them.
      def tags_missing
        @tags_missing ||= begin
          named = version.tag_ids.uniq + version.blocks.filter_map { |block| block["listed_tag_id"] }
          existing = named.empty? ? Set.new : ::Tag.where(id: named.uniq).pluck(:id).to_set
          named.count { |id| !existing.include?(id) }
        end
      end
    end
  end
end
