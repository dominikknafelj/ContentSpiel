module Admin
  module FormsScreen
    # The builder: one column of cards in Settings' card frame
    # (`Admin::Ui::SettingsCardComponent`, each with the Forms chip), ONE form
    # with ONE explicit Save (`Admin::Ui::SaveBarComponent`), then the trash
    # zone after the form, at the column's end.
    #
    #   1. "Form": the name (the default language's tab only: it is no text a
    #      visitor reads, and it is not translated).
    #   2. "Fields": a row per field (`FieldRowComponent`), and the picker,
    #      a paper well titled "Add a field" holding one button per registered
    #      type, each appending a row from its `<template>`
    #      (`admin--forms--builder`).
    #   3. "After sending": the submit label and the thank-you.
    #   4. "Where submissions go" (`DestinationsComponent`).
    #   Then "Placed on" (`PlacementsComponent`), which holds no input, and the
    #   save bar.
    #
    # Everything drawn comes from a `Draft` (the stored form, or what was
    # posted after a refusal or a stale save), so a redraw keeps every typed
    # value and every unsaved row. Nothing of a destination's secret is
    # drawn, and nothing here reads a submission.
    #
    # LANGUAGES: `locale` is the tab. On the default
    # language's tab everything is drawn; on another, only the texts a
    # visitor reads, each with the default language's text above it as a
    # reference line, and the structure is the stored form's (`Draft`).
    #
    # REFUSALS are `Forms::Save`'s sentences, which name no field: the ones
    # this screen can place (the name, a field's label, a choice field, the
    # mail's recipients, "somewhere to send") link to their field from the
    # summary and stand in that field's slot as well (`error_places`). Such
    # a field is `aria-invalid` and takes the shared invalid edge from its
    # `.admin-field` wrapper, whose error slot is its direct child.
    class BuilderComponent < Admin::AdminComponent
      FORM_ID = "form-builder".freeze

      # Every card of a form (the builder's, Where submissions go, Placed on
      # and a submission's) wears the Forms module's chip, read from the
      # sidebar's registry (`StudioModules`), so it follows the sidebar's
      # icon and family.
      def self.card_chip
        entry = ::StudioModules.find(:forms)
        { icon: entry.icon, family: entry.family }
      end

      def initialize(form:, draft:, locale:, placements:, errors: [], mail_settings: nil, keys: nil, dirty: false,
        stale: false, stale_change: nil, base: nil, url_options: {})
        @form = form
        @draft = draft
        @locale = locale.to_s
        @placements = placements
        @errors = Array(errors)
        @mail_settings = mail_settings
        @keys = keys
        @dirty = dirty
        @stale = stale
        @stale_change = stale_change
        @base = base
        @url_options = url_options
      end

      def self.field_id(row, part) = "form-field-#{row}-#{part}"

      private

      attr_reader :form, :draft, :locale, :placements, :errors, :stale_change, :url_options

      def mail_settings = @mail_settings || MailSettings.current

      def keys? = @keys.nil? ? Forms::Encryption.available? : @keys

      def default_locale = Locales.default

      def default_tab? = locale == default_locale

      def languages? = Locales.enabled.size > 1

      def default_language = Locales.name(default_locale)

      def stale? = @stale

      # The form keeps submissions as stored, and holds some.
      def kept_submissions? = form.persisted? && form.keep_submissions_in_database && form.submissions.exists?

      def dirty? = @dirty || stale? || errors.any?

      def heading = form.name_was.presence || form.name

      def base = @base.presence || form.updated_at.iso8601(6)

      def update_path = helpers.admin_form_path(form, **url_options)

      def cancel_path = update_path

      def tab_url = ->(code) { helpers.admin_form_path(form, **(code == default_locale ? {} : { locale: code })) }

      def field_types = Forms::FieldTypes.all

      def max_fields = Forms::Form::MAX_FIELDS

      def full? = draft.rows.size >= max_fields

      # The words `admin--forms--builder` writes into the page, written out
      # here (test/lib/script_messages_test.rb reads this call's literals).
      def messages
        messages_data("components.forms_screen.builder.moved", "components.forms_screen.builder.removed", "components.forms_screen.builder.added",
          "components.forms_screen.field_row.up", "components.forms_screen.field_row.down", "components.forms_screen.field_row.remove_label",
          "components.forms_screen.field_row.no_label", "components.forms_screen.choice_row.up", "components.forms_screen.choice_row.down",
          "components.forms_screen.choice_row.remove_label", "components.forms_screen.choice_row.number")
      end

      def name_id = "form-name"

      def text_id(attribute) = "form-#{attribute}-#{locale}"

      def text_value(attribute) = draft.public_send(attribute).to_h[locale].to_s

      def reference(attribute)
        return if default_tab?

        text = draft.public_send(attribute).to_h[default_locale].presence
        t("admin.components.forms_screen.field_row.reference", language: default_language, text: text) if text
      end

      # A blank row of each type, for its `<template>`: the script replaces
      # `__ROW__` with the new row's name. A choice starts with two empty
      # choices.
      def template_row(type)
        choices = (Array.new(2) { |index| Draft::ChoiceRow.new(row: "__CHOICE#{index}__", key: "", label: {}) } if type.options.include?(:choices))
        Draft::Row.new(row: "__ROW__", key: "", type: type.name, required: false, label: {}, help: {},
          display: (Forms::Field::DISPLAYS.first if type.options.include?(:display)), choices: choices)
      end

      # One empty choice of a field, for the choice `<template>` of the rows:
      # `__ROW__` is the field's row, `__CHOICE__` the new choice's.
      def template_choice = Draft::ChoiceRow.new(row: "__CHOICE__", key: "", label: {})

      # { place => [sentence] } and { place => element id }: each refusal at
      # the one place it is about, else none (the summary prints it as it is).
      def error_places
        @error_places ||= begin
          places = Hash.new { |hash, key| hash[key] = [] }
          errors.each { |sentence| places[place_of(sentence)] << sentence }
          places
        end
      end

      def errors_at(place) = error_places.fetch(place, [])

      def summary_ids
        ids = { "name" => name_id, "destinations" => "form-destinations", "mail" => DestinationsComponent::RECIPIENTS_ID }
        draft.rows.each { |row| ids["row-#{row.row}"] = self.class.field_id(row.row, "label") }
        ids
      end

      def place_of(sentence)
        return "name" if [ Forms::Save.sentence(:name_blank), Forms::Save.sentence(:name_too_long, count: Forms::Form::NAME_MAX) ].include?(sentence)
        return "destinations" if [ Forms::Save.sentence(:nowhere), Forms::Save.sentence(:keep_days, min: Forms::Form::KEEP_DAYS.min, max: Forms::Form::KEEP_DAYS.max) ].include?(sentence)

        draft.rows.each_with_index do |row, index|
          name = row.label[default_locale].presence || Forms::Save.sentence(:field_at, position: index + 1)
          field_sentences = [ Forms::Save.sentence(:label_missing, position: index + 1, language: default_language),
            Forms::Save.sentence(:choices_missing, field: name), Forms::Save.sentence(:too_many_choices, field: name, count: Forms::Form::MAX_CHOICES),
            Forms::Save.sentence(:choice_label_missing, field: name, language: default_language) ]
          return "row-#{row.row}" if field_sentences.include?(sentence)
        end
        place_of_mail(sentence)
      end

      # The mail section's own refusals: a blank required setting, and what
      # the mail deliverer says of its recipients.
      def place_of_mail(sentence)
        mail = draft.section(DestinationsComponent::MAIL)
        type = Forms::DestinationTypes.find(DestinationsComponent::MAIL)
        return "base" unless mail.enabled && type

        sentences = type.fields.map { |field| I18n.t("admin.forms.destinations.blank", field: field.label) }
        sentences += Forms::Destinations::Mail.settings_errors(mail.settings)
        sentences.include?(sentence) ? "mail" : "base"
      end
    end
  end
end
