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
  # nothing to diff, and the caller shows the other side whole.
  module TextDiff
    Entry = Data.define(:label, :before, :after, :result)

    # What a text is, per side: the lines shown, and the paragraphs compared.
    Text = Data.define(:shown, :compared)

    FIELD_NAMES = "admin.components.editor_screen.changes_overview.field_names".freeze

    module_function

    def field(changes, name, locale:)
      translated = Changes::TRANSLATED.fetch(changes.record.class.polymorphic_name).include?(name)
      was, now = changes.sides.map { |side| field_text(side["fields"][name], locale, translated) }
      Entry.new(label: I18n.t(name, scope: FIELD_NAMES, default: name.humanize), before: was.shown, after: now.shown, result: diff(was, now))
    end

    def block(changes, change, locale:)
      was, now = changes.sides_of(change).map { |stored| stored && block_text(stored, locale) }
      Entry.new(label: block_label(change.block), before: was&.shown, after: now&.shown, result: was && now ? diff(was, now) : nil)
    end

    def diff(was, now) = Translations::SourceDiff.call(from: was.compared, to: now.compared)

    def field_text(value, locale, translated)
      value = value[locale.to_s] if translated && value.is_a?(Hash)
      text_of(value)
    end

    # A block's words in `locale`: its body, caption and alt, then each field
    # of its schema that holds text, named by the schema's label.
    def block_text(stored, locale)
      parts = [ text_of(language(stored["body"], locale)) ]
      %w[caption alt].each do |column|
        value = language(stored[column], locale).to_s
        parts << Text.new(shown: "#{column.humanize}: #{value}", compared: [ "#{column.humanize}: #{value}" ]) if value.present?
      end
      settings_lines(stored, locale).each { |line| parts << Text.new(shown: line, compared: [ line ]) }
      parts = parts.reject { |part| part.shown.blank? }
      Text.new(shown: parts.map(&:shown).join("\n\n"), compared: parts.flat_map(&:compared))
    end

    def settings_lines(stored, locale)
      definition = BlockTypes.find(stored["block_type"])
      return [] unless definition

      translated = language(stored["translated_settings"], locale) || {}
      values = (stored["settings"] || {}).merge(translated.is_a?(Hash) ? translated : {})
      definition.fields.filter_map do |field|
        value = values[field.name]
        "#{field.label}: #{value.is_a?(String) ? value : value.to_json}" unless value.blank?
      end
    end

    def language(value, locale) = value.is_a?(Hash) ? value[locale.to_s] : nil

    def text_of(value)
      if value.is_a?(Hash) && value["type"] == "doc"
        document = RichText::Document.new(value)
        Text.new(shown: document.to_markdown.strip, compared: document.plain_paragraphs)
      else
        string = value.is_a?(String) ? value : (value.nil? ? "" : value.to_json)
        Text.new(shown: string, compared: string)
      end
    end

    # A block's name as the editor says it: its type's name, or the stored
    # type's when that type is no longer registered.
    def block_label(block)
      BlockTypes.find(block.block_type)&.label || block.block_type.to_s.humanize
    end
  end
end
