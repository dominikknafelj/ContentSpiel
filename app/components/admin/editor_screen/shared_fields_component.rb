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
    # flat, so it is summarised).
    class SharedFieldsComponent < Admin::AdminComponent
      def self.display(field, value)
        case field.type
        when :boolean then value ? "Yes" : "No"
        when :groups then (count = Array(value).size).zero? ? nil : "#{count} #{"entry".pluralize(count)}"
        when :group then value.present? ? "Set" : nil
        else value.to_s
        end
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
