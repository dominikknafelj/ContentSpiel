module Admin
  module Ui
    # What "Publish changes" will change, worded from `Publishing::Changes`
    # (drafts spec §3): blocks changed, added, removed and moved, each by its
    # type and a line of what is in it; the record's own fields; the
    # languages; the live pages and posts that will LOSE THEIR ADDRESS when
    # this is published (`lost`, from `Publishing::Changes.addresses`:
    # information, nothing is refused for it, except the record's own, which
    # is what a publish is refused for) and, in a second group under the
    # same heading, those that will MOVE TO ANOTHER ADDRESS (`moved`, old
    # and new, and whether the old one redirects: a hand test found a post
    # that moved from `/blog/x` to `/x` named nowhere); and, when another
    # tab holds part of the record, that only what has been saved is
    # published.
    #
    # The answer to the dialog's POST (`Admin::PublishingController#changes`),
    # put into the dialog by `admin--editor--publish-dialog`. One element with
    # no id in it: it is drawn beside the editor's own cards.
    #
    # TWO DETAILS. `:names` is the dialogs' (publish, restore, Publish now):
    # what changed, by name. `:diffs` is the History screen's comparison of
    # two versions in ONE language (`locale`): each field that differs in it,
    # by its label over its words (`Publishing::TextDiff`, drawn by
    # `WordDiffComponent`), then each block in reading order with a changed
    # block's words under its row and a moved one's places. Nothing of a
    # publish is said there (no schedule facts, addresses or holders: nothing
    # is published from it), and a field that differs only in another
    # language is not shown, since its words here are the same.
    class ChangesOverviewComponent < Admin::AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "Headings over lists of what changed; a diff's removed and added words carry WordDiff's screen-reader cues, and the only Tab stops are the links to the records that lose or move their address.",
        motion: :none,
        content_edges: %i[long many none],
        widths: :from_container,
        interface: %i[record changes holds locale detail lost moved url_options schedule_only],
        limits: [
          "It words the comparison it is handed and decides no change itself: the diffs detail asks Publishing::TextDiff for each entry's words.",
          "In the diffs detail it compares one language, and draws no schedule facts, addresses or holders.",
          "A structured value with no words (a list's rows, a hero image) is named as changed, never drawn."
        ],
        states: %i[names diffs none],
        keys: %w[
          none none_scheduled compared_with_scheduled blocks fields.page fields.post languages kinds.changed kinds.added kinds.removed kinds.moved
          untitled held.page held.post lost_addresses.heading lost_addresses.body.page lost_addresses.body.post lost_addresses.hidden
          moved_addresses.body.page moved_addresses.body.post moved_addresses.change moved_addresses.own.page moved_addresses.own.post
          moved_addresses.no_redirect moved_addresses.hidden own_address.page own_address.post
          schedule.kept schedule.discard schedule.cancel schedule.cancel_gone
          diffs.fields.page diffs.fields.post diffs.none diffs.formatting diffs.too_long diffs.moved_to diffs.opaque
        ],
        slots: [],
        controller: nil,
        keyboard: [ "test/system/admin/drafts_test.rb", "the dialog's overview takes the keyboard to a lost address's link with Tab, and Enter there opens that record" ]
      )

      DETAILS = %i[names diffs].freeze
      KINDS = %i[changed added removed moved].freeze
      SUMMARY_LENGTH = 80
      Lost = Data.define(:record, :path, :locales)
      Moved = Data.define(:record, :path, :to, :locales, :redirects)

      # The answer to `part=schedule`: what is scheduled now and nothing else.
      def self.schedule_only(record:) = new(record: record, changes: nil, holds: nil, locale: ::Locales.default, schedule_only: true)

      def initialize(record:, changes:, holds:, locale:, detail: :names, lost: [], moved: [], url_options: {}, schedule_only: false)
        raise ArgumentError, "unknown detail #{detail.inspect}" unless DETAILS.include?(detail)

        @detail = detail
        @schedule_only = schedule_only
        @record = record
        @changes = changes
        @holds = holds
        @locale = locale.to_s
        @lost = lost
        @moved = moved
        @url_options = url_options
      end

      def type = record.is_a?(::Page) ? "page" : "post"

      def schedule_only? = @schedule_only

      def diffs? = @detail == :diffs

      # WHAT IS SCHEDULED NOW, for the dialogs' scripts (`admin--editor--publish-dialog`):
      # the pending copy's id (what each form sends back as `pending`, so
      # the server can refuse a press made on older news) and the three
      # sentences that name its time, each whole, as the dialogs show them.
      # Empty attributes when nothing is scheduled.
      def schedule_facts
        pending = ::Publishing.pending(record)
        return { publishing_schedule: "", pending_id: "", cancel_line: t(".schedule.cancel_gone") } unless pending

        time = I18n.l(pending.live_at.in_time_zone(Current.site.effective_time_zone), format: :"admin.datetime")
        { publishing_schedule: "", pending_id: pending.id, kept_label: t(".schedule.kept", time: time),
          discard_line: t(".schedule.discard", time: time), cancel_line: t(".schedule.cancel", time: time) }
      end

      def none? = changes.none?

      def blocks = changes.blocks.sort_by { |entry| KINDS.index(entry.kind) }

      def kind_label(entry) = t(".kinds.#{entry.kind}")

      def type_label(entry) = ::Publishing::TextDiff.block_label(entry.block)

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
      def field_labels = changes.fields.map { |name| t(name, scope: ::Publishing::TextDiff::FIELD_NAMES, default: name.humanize) }.uniq # i18n-ok: a column with no key is named by its own name, humanised, as TextDiff names it

      def language_names = changes.locales.map { |code| ::Locales.name(code) }

      def scheduled_baseline? = changes.version&.live_at&.future? || false

      def baseline_time = I18n.l(changes.version.live_at.in_time_zone(Current.site.effective_time_zone), format: :"admin.datetime")

      # Whoever holds a part of this record in another tab: their unsaved
      # text is not in the rows, so it is not published.
      def holders
        return [] unless holds

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

      def lost_languages(entry) = entry.locales.map(&:upcase).to_sentence # i18n-ok: to_sentence joins with the locale's support.array words

      # THE RECORDS THAT WOULD MOVE, the record's own among them (a post
      # whose published tags take it to another list): one line per record
      # and pair of addresses, with the languages it holds for, so a record
      # that moves alike in every language is one line. Only those the
      # viewer may read are named, the rest counted (`hidden_moved`), as for
      # the losses. A move is not a refusal: the old address redirects,
      # unless another record takes it in the same publish (`redirects`,
      # read from the trial itself: `PublicSite::Paths.foresee`).
      def moved_entries
        @moved_entries ||= begin
          readable = readable_records(moved)
          @hidden_moved = (moved.map { |row| row.values_at(:record_type, :record_id) }.uniq - readable.keys).size
          moved.group_by { |row| row.values_at(:record_type, :record_id, :path, :to, :redirects) }.filter_map do |(type, id, path, to, redirects), rows|
            found = readable[[ type, id ]] or next
            Moved.new(record: found, path: path, to: to, locales: rows.map { |row| row[:locale] }.sort, redirects: redirects)
          end
        end
      end

      def hidden_moved = moved_entries && @hidden_moved

      def own?(entry) = entry.record == record

      def addresses? = others_lost.any? || hidden_lost.to_i.positive? || moved_entries.any? || hidden_moved.positive?

      # -- detail: :diffs --------------------------------------------------------

      # The fields that differ in this language, each a `TextDiff::Entry`.
      def field_entries
        @field_entries ||= changes.fields.map { |name| ::Publishing::TextDiff.field(changes, name, locale: locale) }.select { |entry| differs?(entry) }
      end

      # Every changed block in reading order (the copy's order on the later
      # side, a removed block where it stood), each with its words in this
      # language, or nil for an added, removed or moved block, which has no
      # words to compare. A changed block is shown when it differs in THIS
      # language or in what every language shares (its type, its image, its
      # untranslated settings); one changed only in another language is left
      # out, so that a comparison with nothing in this language says so. A
      # field follows the same rule through `differs?`: a shared column reads
      # the same value in every language.
      def block_rows
        @block_rows ||= changes.blocks.sort_by { |change| ordering(change) }.filter_map do |change|
          next [ change, nil ] unless change.kind == :changed

          entry = ::Publishing::TextDiff.block(changes, change, locale: locale)
          words = differs?(entry)
          [ change, words ? entry : nil ] if words || shared_change?(change)
        end
      end

      def none_in_language? = field_entries.empty? && block_rows.empty?

      # "now 4th, was 2nd", by place in each side's reading order.
      def moved_to(change)
        was, now = changes.places_of(change)
        t(".diffs.moved_to", to: now.ordinalize, from: was.ordinalize)
      end

      # The structured values that changed with no words, by their labels.
      def opaque_line(entry)
        return if entry.opaque.empty?

        t(".diffs.opaque", names: entry.opaque.map { |label| part_label(label) }.to_sentence) # i18n-ok: to_sentence joins with the locale's support.array words
      end

      # An entry's words: the diff box, or the line that stands in its place
      # (too long to compare, or only the formatting changed), and the line
      # naming what changed with no words. A paragraph break is a "\n"
      # segment, kept by `whitespace-pre-line`.
      def diff_box(entry)
        result = entry.result
        lines = []
        if result.too_long?
          lines << tag.p(t(".diffs.too_long"), class: "text-small text-meta", data: { diff_too_long: "" })
        elsif result.changed?
          lines << tag.div(render(Admin::Ui::WordDiffComponent.new(segments: result.segments)),
            class: "rounded-tile bg-paper px-3 py-2.5 text-sm leading-[1.6] text-ink whitespace-pre-line", data: { diff: "" })
        elsif entry.opaque.empty?
          lines << tag.p(t(".diffs.formatting"), class: "text-small text-meta", data: { diff_formatting: "" })
        end
        lines << tag.p(opaque_line(entry), class: "text-small text-meta", data: { diff_opaque: "" }) if entry.opaque.any?
        safe_join(lines)
      end

      # The type's icon at a tile's size, never the block's own: an icon that
      # follows its block carries an id, and this element has none.
      def block_icon(change) = Admin::Ui::BlockIconComponent.new(definition: change.block.definition, place: :tile)

      attr_reader :locale

      private

      # Whether an entry's sides differ in this language: a field changed only
      # in another reads the same words on both sides here.
      def differs?(entry) = entry.before != entry.after

      # A content column every language shares differs between the block's
      # two sides (`Changes::BLOCK_CONTENT` less the translated ones).
      def shared_change?(change)
        was, now = changes.sides_of(change)
        (::Publishing::Changes::BLOCK_CONTENT - ::Publishing::Changes::BLOCK_TRANSLATED).any? { |name| was[name] != now[name] }
      end

      def part_label(label) = label.is_a?(Symbol) ? t(label, scope: "admin.publishing.text_diff.parts") : label

      # A block on the later side by its place there; a removed one by the
      # place it had, after a block that now stands at that number.
      def ordering(change)
        was, now = changes.places_of(change)
        now ? [ now, 0 ] : [ was, 1 ]
      end

      attr_reader :record, :changes, :holds, :lost, :moved, :url_options

      def grouped_lost
        @grouped_lost ||= begin
          rows = lost.group_by { |row| [ row[:record_type], row[:record_id] ] }
          readable = readable_records(lost)
          @hidden_lost = (rows.keys - readable.keys).size
          rows.filter_map do |key, entries|
            Lost.new(record: readable[key], path: entries.first[:path], locales: entries.map { |entry| entry[:locale] }.sort) if readable[key]
          end
        end
      end

      # `{ [record type, id] => record }` for the records these rows name
      # that the viewer may read: a title out of scope is never shown.
      def readable_records(rows)
        rows.map { |row| row.values_at(:record_type, :record_id) }.uniq.group_by(&:first).flat_map do |record_type, keys|
          klass = record_type == ::Page.polymorphic_name ? ::Page : ::Post
          AccessControl.scope(Current.actor, "#{record_type.downcase}s.read", klass.kept.where(id: keys.map(&:last))).to_a
        end.index_by { |found| [ found.class.polymorphic_name, found.id ] }
      end
    end
  end
end
