module Admin
  module Fields
    # A `<select>` of the forms, for the Form block's `:form` field (forms
    # plan, Task 7; spec decision 10: placing a form needs only the right to
    # edit the page, and the picker lists every form by name). The choices
    # are every KEPT form by name, each drawn as escaped text, after "Choose
    # a form", which stores nothing. A stored id that no kept form has (the
    # form was trashed or purged after it was placed) is drawn first,
    # selected and named "A form that's gone", so a save keeps it until
    # someone picks another; the public page draws nothing for it.
    class FormField < Base
      # The form's name, or the gone word; nil for none chosen.
      def self.display(_field, value)
        return nil if value.blank?

        kept.find_by(id: value.to_s)&.name || I18n.t("admin.components.fields.form_field.gone")
      end

      def self.kept = ::Forms::Form.kept

      # `[text, value]` pairs for `options_for_select`: a gone stored id
      # first, then the empty choice, then the kept forms by name.
      def option_pairs
        known = self.class.kept.order(:name, :id).pluck(:name, :id).map { |name, id| [ name, id.to_s ] }
        gone = value.present? && known.none? { |_name, id| id == value.to_s } ? [ [ t(".gone"), value.to_s ] ] : []
        gone + [ [ t(".choose"), "" ] ] + known
      end
    end
  end
end
