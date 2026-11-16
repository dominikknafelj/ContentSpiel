module Publishing
  # The words that differ between the two sides of a `Publishing::Changes`, in
  # ONE language, for one field or one block: the version history's word diff
  # (`Translations::SourceDiff`, with its limits, drawn by
  # `Admin::Ui::WordDiffComponent`). Pure reading of the stored forms
  # `Changes#sides` and `#sides_of` hold; no row is read, so a version compares
  # as it was taken.
  #
  # A rich-text document is shown as its Markdown (`before`, `after`) and
  # compared by its paragraphs' plain text, as the translation pair does: a
  # change that leaves the words alone (bold, a heading made a paragraph) has
  # no segments and reads `formatting_only?`, where comparing the Markdown
  # would report the asterisks as words.
  #
  # `result` is nil when a side is absent (an added or removed block): there is
  # nothing to diff, and the caller shows the other side whole. `before` and
  # `after` are lists of `Part`s (nil for an absent side); a field is one part
  # with no label.
  module TextDiff
    Entry = Data.define(:label, :before, :after, :result, :opaque)

    # `label`: a Symbol, a String (a schema field's label) or nil; `shown`: the
    # text as drawn (Markdown for a document), nil for a structured value;
    # `compared`: what the diff reads, a String or paragraphs.
    Part = Data.define(:label, :shown, :compared) do
      def opaque? = shown.nil?
    end

    FIELD_NAMES = "admin.publishing.text_diff.field_names".freeze

    module_function

    def field(changes, name, locale:)
      translated = Changes::TRANSLATED.fetch(changes.record.class.polymorphic_name).include?(name)
      was, now = changes.sides.map { |side| [ name == "tags" ? tags_part(side) : field_part(side["fields"][name], locale, translated, reference: name.end_with?("_id")) ] }
      label = I18n.t(name, scope: FIELD_NAMES, default: name.humanize)
      # A field's part has no label, so what changed is `[nil]`: asked for
      # emptiness, never `any?`.
      Entry.new(label:, before: was, after: now, result: diff(was, now), opaque: opaque_changes(was, now).empty? ? [] : [ label ])
    end

    def block(changes, change, locale:)
      was, now = changes.sides_of(change).map { |stored| stored && block_parts(stored, locale) }
      both = was && now
      Entry.new(label: block_label(change.block), before: was, after: now, result: both ? diff(was, now) : nil, opaque: both ? opaque_changes(was, now) : [])
    end

    def diff(was, now) = Translations::SourceDiff.call(from: compared(was), to: compared(now))

    # The values of the parts that have words, as paragraphs.
    def compared(parts) = parts.reject(&:opaque?).flat_map { |part| Array(part.compared) }

    # The labels whose structured value differs between the sides.
    def opaque_changes(was, now)
      by_label = ->(parts) { parts.select(&:opaque?).to_h { |part| [ part.label, part.compared ] } }
      before, after = by_label.(was), by_label.(now)
      (before.keys | after.keys).select { |label| before[label] != after[label] }
    end

    # A reference to another row (`hero_media_asset_id`) is a value with no
    # words: its number is no text a person wrote.
    def field_part(value, locale, translated, reference: false)
      value = value[locale.to_s] if translated && value.is_a?(Hash)
      reference ? opaque(nil, value) : text_part(nil, value)
    end

    # A post's tags are not a field of the side but its own list
    # (`Snapshot#tags_of`), compared as their names in alphabetical order.
    def tags_part(side) = text_part(nil, side.fetch("tags", []).map { |tag| tag["name"] }.sort.join(", "))

    # A block's words in `locale`: its body, caption and alt, then each field
    # of its schema that holds a value, named by the schema's label.
    def block_parts(stored, locale)
      parts = [ text_part(:body, language(stored["body"], locale)) ]
      %w[caption alt].each { |column| parts << text_part(column.to_sym, language(stored[column], locale)) }
      parts.concat(settings_parts(stored, locale))
      parts.reject { |part| !part.opaque? && part.shown.blank? }
    end

    def settings_parts(stored, locale)
      definition = BlockTypes.find(stored["block_type"])
      return [] unless definition

      translated = language(stored["translated_settings"], locale)
      values = (stored["settings"] || {}).merge(translated.is_a?(Hash) ? translated : {})
      definition.fields.filter_map do |field|
        value = values[field.name]
        next if value.blank?

        text_part(field.label, value)
      end
    end

    def language(value, locale) = value.is_a?(Hash) ? value[locale.to_s] : nil

    def text_part(label, value)
      case value
      when Hash
        return opaque(label, value) unless value["type"] == "doc"

        document = RichText::Document.new(value)
        Part.new(label:, shown: document.to_markdown.strip, compared: document.plain_paragraphs)
      when Array
        value.any? { |item| item.is_a?(Hash) || item.is_a?(Array) } ? opaque(label, value) : text_part(label, value.join(", "))
      when nil then Part.new(label:, shown: "", compared: "")
      else Part.new(label:, shown: value.to_s, compared: value.to_s)
      end
    end

    def opaque(label, value) = Part.new(label:, shown: nil, compared: value)

    # A block's name as the editor says it: its type's name, or the stored
    # type's when that type is no longer registered.
    def block_label(block)
      BlockTypes.find(block.block_type)&.label || block.block_type.to_s.humanize
    end
  end
end
