module Admin
  module Fields
    # A `<select>` of one of the lists the theme declares in theme.yml, for
    # `:theme_choice` fields. The choices are the theme's entries in the
    # theme's order, each by its label in the interface language, always
    # drawn as escaped text: CS Studio shows nothing else of a theme (no
    # template, stylesheet, script or inlined SVG), and an icon's file is
    # only ever an `<img>` of its served address where a picture is wanted
    # (`Theme#icon_asset`), never inside an option.
    #
    # The first option is the default: no style, no icon. A stored name the
    # theme does not declare (a theme that dropped it, or another theme) is
    # drawn first, selected and marked "not in this theme", so the save
    # keeps it unless someone picks another; it is shown even when the list
    # is empty. With an empty list and nothing stored there is nothing to
    # choose and nothing is drawn, label included (`Ui::FieldComponent`
    # asks `render?` of its input).
    class ThemeChoiceField < Base
      # The label in the interface language, the blank's word, or the stored
      # name marked as unknown.
      def self.display(field, value)
        return blank_word(field) if value.blank?

        entry = entries(field).find { |candidate| candidate.name == value.to_s }
        entry ? entry.label_for(I18n.locale) : unknown_word(value)
      end

      def self.entries(field) = Array(ContentModel.theme_choices.call(field.options[:of].to_sym))

      def self.blank_word(field)
        I18n.t("admin.components.fields.theme_choice_field.#{field.options[:of] == :icons ? "no_icon" : "default"}")
      end

      def self.unknown_word(value) = I18n.t("admin.components.fields.theme_choice_field.not_in_theme", name: value)

      # Whether the input (and so the field's label) is drawn at all.
      def self.draws?(field, value) = entries(field).any? || (value.present? && entries(field).none? { |entry| entry.name == value.to_s })

      def render? = self.class.draws?(field, value)

      # `[text, value]` pairs for `options_for_select`: an unknown stored
      # name first, then the blank, then the theme's entries.
      def option_pairs
        known = entries.map { |entry| [ entry.label_for(I18n.locale), entry.name ] }
        unknown = value.present? && entries.none? { |entry| entry.name == value.to_s } ? [ [ self.class.unknown_word(value), value.to_s ] ] : []
        unknown + [ [ self.class.blank_word(field), "" ] ] + known
      end

      # The served address of the stored icon's file, for the picture beside
      # the select: an `<img>`, so the theme's SVG is never inlined into CS
      # Studio (it is shown as a picture, which runs no script). nil for any
      # other list and for a blank or undeclared name.
      def icon_source
        return unless field.options[:of] == :icons

        asset = Theme.current.icon_asset(value)
        helpers.image_path(asset) if asset
      end

      def entries = @entries ||= self.class.entries(field)
    end
  end
end
