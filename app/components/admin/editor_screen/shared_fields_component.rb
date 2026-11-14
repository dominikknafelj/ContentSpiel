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
    # flat, so it is summarised). A select is shown by its label and code
    # (`Admin::Fields::CodeDisplay`) in a scrolling `pre`, both read-only like
    # the rest.
    #
    # CODE KEEPS ITS FRAME (design answer C6): the sunken ground, a line
    # around it, the monospace face in full ink. One 12px line above it says
    # that code is not translated and on which tab it is edited, and the
    # language's name in that line is a link to that tab: the same top-level
    # visit the header's language tab makes (`Admin::Ui::LanguageTabsComponent`:
    # a link with `data-turbo-frame="_top"`), so the leave guard hears of it
    # as it does of the tab. `primary_url:` is that address, the caller's to
    # know; without one the name is plain text.
    #
    # The `pre`'s template writes a line break after the opening tag: a
    # browser drops the first one there, and with it the value's own if the
    # value began with one. A stored value never does
    # (the `:code` type's cast, `ContentModel::FieldTypes`), but this component is handed
    # whatever its caller read.
    class SharedFieldsComponent < Admin::AdminComponent
      # A scalar reads as its input says (`Admin::Fields::<Type>Field.display`);
      # a nested group or list can't be shown flat, so it is summarised.
      def self.display(field, value)
        case field.type
        when :groups then (count = Array(value).size).zero? ? nil : "#{count} #{"entry".pluralize(count)}"
        when :group then value.present? ? "Set" : nil
        else "Admin::Fields::#{field.type.to_s.camelize}Field".constantize.display(field, value)
        end
      end

      # Whether a field has a row here: not a hidden input nobody types in
      # (`Admin::Fields::Base.hidden?`, a drawing), which has nothing to read.
      def self.listed?(field)
        field.group? || !Admin::Ui::FieldComponent.input_class_for(field).hidden?(field)
      end

      def initialize(fields:, primary_url: nil)
        @fields = fields
        @primary_url = primary_url
      end

      attr_reader :fields, :primary_url

      def render? = fields.any?

      def count = fields.size

      def primary_name = ::Locales.name(::Locales.default, native: true)

      # "Code isn't translated. Edit it on the English tab.", the name linked.
      def code_note = t(".code_not_translated_html", language: primary_link)

      def primary_link
        return primary_name if primary_url.blank?

        helpers.link_to(primary_name, primary_url, class: "underline hover:text-ink", data: { turbo_frame: "_top" })
      end
    end
  end
end
