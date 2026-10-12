module Admin
  module EditorScreen
    # What "Publish changes" will change, worded from `Publishing::Changes`
    # (drafts spec §3): blocks changed, added, removed and moved, each by its
    # type and a line of what is in it; the record's own fields; the
    # languages; the live pages and posts that will LOSE THEIR ADDRESS when
    # this is published (`lost`, from `Publishing::Changes.lost_addresses`:
    # information, nothing is refused for it, except the record's own, which
    # is what a publish is refused for); and, when another tab holds part of
    # the record, that only what has been saved is published.
    #
    # The answer to the dialog's POST (`Admin::PublishingController#changes`),
    # put into the dialog by `admin--editor--publish-dialog`. One element with
    # no id in it: it is drawn beside the editor's own cards.
    class ChangesOverviewComponent < Admin::AdminComponent
      KINDS = %i[changed added removed moved].freeze
      DIALOG = "admin.components.editor_screen.publish_changes_dialog".freeze
      SUMMARY_LENGTH = 80
      Lost = Data.define(:record, :path, :locales)

      # The answer to `part=schedule`: what is scheduled now and nothing else.
      def self.schedule_only(record:) = new(record: record, changes: nil, holds: nil, locale: ::Locales.default, schedule_only: true)

      def initialize(record:, changes:, holds:, locale:, lost: [], url_options: {}, schedule_only: false)
        @schedule_only = schedule_only
        @record = record
        @changes = changes
        @holds = holds
        @locale = locale.to_s
        @lost = lost
        @url_options = url_options
      end

      def type = record.is_a?(::Page) ? "page" : "post"

      def schedule_only? = @schedule_only

      # WHAT IS SCHEDULED NOW, for the dialogs' scripts (`admin--editor--publish-dialog`):
      # the pending copy's id (what each form sends back as `pending`, so
      # the server can refuse a press made on older news) and the three
      # sentences that name its time, each whole, as the dialogs show them.
      # Empty attributes when nothing is scheduled.
      def schedule_facts
        pending = ::Publishing.pending(record)
        return { publishing_schedule: "", pending_id: "", cancel_line: t("#{DIALOG}.cancel_scheduled_gone") } unless pending

        time = I18n.l(pending.live_at.in_time_zone(Current.site.effective_time_zone), format: :"admin.datetime")
        { publishing_schedule: "", pending_id: pending.id, kept_label: t("#{DIALOG}.kept", time: time),
          discard_line: t("#{DIALOG}.discard_scheduled", time: time), cancel_line: t("#{DIALOG}.cancel_scheduled_body", time: time) }
      end

      def none? = changes.none?

      def blocks = changes.blocks.sort_by { |entry| KINDS.index(entry.kind) }

      def kind_label(entry) = t(".kinds.#{entry.kind}")

      def type_label(entry) = entry.block.definition&.label || entry.block.block_type.to_s.humanize

      # One line of what the block holds, as its tile says it: the first
      # paragraph, or the image's file name. A section and a list are named
      # by their type alone. Written here and not through the tile's own
      # component, which carries the id of the tile on this very page.
      def summary(entry)
        block = entry.block
        columns = block.definition&.uses_columns || []
        if columns.include?("image") then block.media_asset&.file&.filename.to_s.presence
        elsif columns.include?("body") then block.body_document(locale: locale).plain_paragraphs.first.to_s.truncate(SUMMARY_LENGTH).presence
        end
      end

      # The record's own fields, each by the name its form gives it, once (a
      # post type's own fields are two columns and one name).
      def field_labels = changes.fields.map { |name| t(".field_names.#{name}", default: name.humanize) }.uniq

      def language_names = changes.locales.map { |code| ::Locales.name(code) }

      def scheduled_baseline? = changes.version&.live_at&.future? || false

      def baseline_time = I18n.l(changes.version.live_at.in_time_zone(Current.site.effective_time_zone), format: :"admin.datetime")

      # Whoever holds a part of this record in another tab: their unsaved
      # text is not in the rows, so it is not published.
      def holders
        subjects = [ record, *(record.is_a?(::Page) ? ::ContentBlock.where(owner: record).to_a : []) ]
        subjects.filter_map { |subject| holds.other(subject)&.user }.uniq
      end

      # The record's OWN address among what would be lost: the one case a
      # publish is refused for (`Publishing.keep_address!`).
      def own_lost = grouped_lost.find { |entry| entry.record == record }

      # The other live records that would be left without an address, each
      # once with the languages it loses it in. Only those the viewer may
      # read are named; the rest are counted (`hidden_lost`): a title out of
      # the viewer's scope is not shown, here as anywhere.
      def others_lost = grouped_lost.reject { |entry| entry.record == record }

      def hidden_lost = grouped_lost && @hidden_lost

      def lost_title(entry) = ::Locales.read(entry.record, :title, locale: locale).presence || t(".untitled")

      def lost_url(entry)
        entry.record.is_a?(::Page) ? helpers.admin_page_path(entry.record, **url_options) : helpers.admin_post_path(entry.record, **url_options)
      end

      def lost_languages(entry) = entry.locales.map(&:upcase).to_sentence

      attr_reader :locale

      private

      attr_reader :record, :changes, :holds, :lost, :url_options

      def grouped_lost
        @grouped_lost ||= begin
          rows = lost.group_by { |row| [ row[:record_type], row[:record_id] ] }
          readable = rows.keys.group_by(&:first).flat_map do |record_type, keys|
            klass = record_type == "Page" ? ::Page : ::Post
            AccessControl.scope(Current.actor, "#{record_type.downcase}s.read", klass.kept.where(id: keys.map(&:last))).to_a
          end.index_by { |found| [ found.class.polymorphic_name, found.id ] }
          @hidden_lost = (rows.keys - readable.keys).size
          rows.filter_map do |key, entries|
            Lost.new(record: readable[key], path: entries.first[:path], locales: entries.map { |entry| entry[:locale] }.sort) if readable[key]
          end
        end
      end
    end
  end
end
