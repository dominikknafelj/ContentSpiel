module Admin
  module EditorScreen
    # The collapsed "Shared fields (N)" disclosure (handoff §10 B23) a
    # translation tab shows in place of every field that is the same in all
    # languages: its label and current value, read only, with the note saying
    # where to edit them. An untranslated field has no per-language value, so
    # on a translation tab it is not an input at all -- and so never part of
    # that tab's autosave PATCH, which therefore cannot touch it.
    #
    # `fields:` is a list of `[label, value]` pairs; `.display` turns a typed
    # field's value into the text shown (a nested group or list can't be shown
    # flat, so it is summarised). A select is shown by its label and code in a
    # scrolling `pre`, both read-only like the rest.
    class SharedFieldsComponent < Admin::AdminComponent
      # Code shown read-only: the template draws it in a `pre`, not as a line of text.
      Code = Data.define(:text)

      def self.display(field, value)
        case field.type
        when :boolean then value ? "Yes" : "No"
        when :groups then (count = Array(value).size).zero? ? nil : "#{count} #{"entry".pluralize(count)}"
        when :group then value.present? ? "Set" : nil
        when :select then select_label(field, value)
        when :code then value.present? ? Code.new(value.to_s) : nil
        else value.to_s
        end
      end

      # The label an editor picked, not the stored value; the empty choice by
      # its own label where it has one; a value that is no longer on the list
      # as it is stored.
      def self.select_label(field, value)
        return field.options[:blank].to_s if value.blank?

        options = field.options[:options]
        (options[value.to_s] if options.is_a?(Hash)) || value.to_s
      end

      def initialize(fields:)
        @fields = fields
      end

      attr_reader :fields

      def render? = fields.any?

      def count = fields.size

      def primary_name = ::Locales.name(::Locales.default, native: true)
    end
  end
end
