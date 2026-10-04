module Admin
  module AuditScreen
    # An audit event's field changes (design pass round 3, Task 15; replaces
    # `Admin::AuditChangesComponent`). `field_changes` is
    # `Audit::Event#field_changes`: `{ "de title" => [old, new] }` for a
    # translated column (the locale and the field in one key),
    # `{ "title" => [old, new] }` for a plain one, `{ "en body" =>
    # { "digest_before", "digest_after" } }` for a rich-text body.
    #
    # Grouped per language -- "2 FIELDS · DEUTSCH" -- then the fields that
    # aren't a language's. A language is named from the enabled languages; one
    # since turned off is labelled by its code. Each field is one row:
    #
    #   * text (a string, or nothing) as a WORD DIFF (`Translations::SourceDiff`,
    #     drawn by `Admin::WordDiffComponent`, the translation reference card's
    #     del/ins look): BEFORE shows the text with what left struck through,
    #     AFTER the text with what came in underlined. An empty side reads
    #     "Empty". Text too long for a word diff (`SourceDiff`'s own bounds, and
    #     `TEXT_LIMIT` before it so a huge string never even reaches it) reads
    #     "The text is too long to compare word by word." with both sides shown
    #     plainly, cut at `SHOWN_LIMIT` characters;
    #   * a rich-text body, or any change that only has digests, reads
    #     "Changed" -- never the digests, never a JSON dump of a document;
    #   * anything else (a flag, a number, a list) as old -> new.
    #
    # Nothing is un-scrubbed: the stored values are already scrubbed of secrets
    # (`Audit::Snapshot`), and a key that the scrub would drop, or that is
    # translation bookkeeping, is skipped here too. Every value is text that
    # ERB escapes -- never `html_safe` -- so a title of literal `<script>` shows
    # as text.
    class ChangesComponent < Admin::AdminComponent
      LOCALE_KEY = /\A([a-z]{2,3}(?:-[A-Za-z0-9]+)?) ([a-z_]+)\z/
      TEXT_LIMIT = 20_000
      SHOWN_LIMIT = 2_000
      TOO_LONG = "The text is too long to compare word by word.".freeze

      Group = Data.define(:code, :heading, :rows)
      Row = Data.define(:field, :kind, :before, :after)

      def initialize(field_changes:)
        @field_changes = field_changes.is_a?(Hash) ? field_changes : {}
      end

      def groups
        @groups ||= begin
          grouped = rows.group_by(&:first)
          ordered = grouped.keys.sort_by { |code| order_of(code) }
          ordered.map do |code|
            group_rows = grouped[code].map(&:last)
            Group.new(code, heading_for(code, group_rows.size), group_rows)
          end
        end
      end

      def empty? = groups.empty?

      # The BEFORE and AFTER cells of one row. An empty side is "Empty"; a side
      # that left or came in is drawn in the diff's own del/ins style.
      def before_html(row)
        case row.kind
        when :diff then render(Admin::WordDiffComponent.new(segments: row.before))
        when :added then empty
        when :removed then render(Admin::WordDiffComponent.new(segments: [ [ :delete, row.before ] ]))
        when :too_long then safe_join([ row.before, tag.p(TOO_LONG, class: "mt-1 text-meta") ])
        else row.before.nil? ? empty : row.before
        end
      end

      def after_html(row)
        case row.kind
        when :diff then render(Admin::WordDiffComponent.new(segments: row.after))
        when :removed then empty
        when :added then render(Admin::WordDiffComponent.new(segments: [ [ :insert, row.after ] ]))
        else row.after.nil? ? empty : row.after
        end
      end

      private

      def empty = content_tag(:span, "Empty", class: "text-meta")

      # `[locale or nil, Row]` for every shown change.
      def rows
        @field_changes.filter_map do |key, value|
          code, field = split_key(key.to_s)
          next if Audit::Snapshot::IGNORED_CHANGES.include?(field) || !Audit::Snapshot.keep?(field)

          [ code, build_row(field, value) ]
        end
      end

      def split_key(key)
        match = LOCALE_KEY.match(key)
        match ? [ match[1], match[2] ] : [ nil, key ]
      end

      # Fields that aren't a language's first, then the enabled languages in
      # their order, then any other code.
      def order_of(code)
        return [ 0, 0, "" ] if code.nil?

        index = ::Locales.enabled.index(code)
        index ? [ 1, index, code ] : [ 2, 0, code ]
      end

      def heading_for(code, count)
        text = "#{count} #{count == 1 ? "FIELD" : "FIELDS"}"
        return text if code.nil?

        name = ::Locales.enabled?(code) ? ::Locales.name(code, native: true) : code.upcase
        "#{text} · #{name.upcase}"
      end

      def build_row(field, value)
        return Row.new(field, :changed, nil, nil) unless value.is_a?(Array) && value.size == 2

        before, after = value
        if textual?(before) && textual?(after)
          text_row(field, before.presence, after.presence)
        else
          Row.new(field, :values, shown(before), shown(after))
        end
      end

      def textual?(value) = value.nil? || value.is_a?(String)

      def text_row(field, before, after)
        return Row.new(field, :values, nil, nil) if before.nil? && after.nil?
        return Row.new(field, :added, nil, cut(after)) if before.nil?
        return Row.new(field, :removed, cut(before), nil) if after.nil?
        return too_long_row(field, before, after) if before.length > TEXT_LIMIT || after.length > TEXT_LIMIT

        diff = Translations::SourceDiff.call(from: before, to: after)
        return too_long_row(field, before, after) if diff.too_long?
        return Row.new(field, :values, cut(before), cut(after)) unless diff.changed?

        Row.new(field, :diff, diff.segments.reject { |kind, _| kind == :insert }, diff.segments.reject { |kind, _| kind == :delete })
      end

      def too_long_row(field, before, after) = Row.new(field, :too_long, cut(before), cut(after))

      def cut(text) = text.length > SHOWN_LIMIT ? "#{text.first(SHOWN_LIMIT)}…" : text

      # A non-text value as the text it would read as; nil is "Empty".
      def shown(value)
        case value
        when nil then nil
        when String then cut(value)
        when Array, Hash then cut(value.to_json)
        else value.to_s
        end
      end
    end
  end
end
