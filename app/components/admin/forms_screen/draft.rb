module Admin
  module FormsScreen
    # What the builder shows and what its Save hands `Forms::Save` (forms
    # plan, Task 4; design.md 2): one value for both, so the screen drawn
    # again after a refusal (422) or a stale base (409) shows exactly what
    # was typed, unsaved rows included, and the save is built from the same
    # reading. `Admin::SettingsScreen::Values` is the same idea for Settings.
    #
    # Read from the stored form (`from_form`) or from what the builder posted
    # over the stored form (`from_params`). A posted field is a hash keyed by
    # its ROW, a name that never moves: the field's key for a stored field,
    # `new-...` for one added in this page (`admin--forms--builder`), and the
    # order is `form[field_order]`, the rows' names in order, one tracked
    # input (so a move is one change for the save bar, not one per input
    # whose index moved). A row removed in the page is left out of the order
    # and dropped here; its inputs may still be posted. A choice is the same
    # inside its field (`choice_order`, `choices[<row>]`).
    #
    # LANGUAGES (design.md 2.5). The builder shows one language at a time,
    # and `Forms::Save` takes every enabled language's texts whole (it keeps
    # only the texts of languages that are switched OFF). So a text the page
    # did not post is the stored one: every text is the stored form's,
    # overlaid with the languages posted. On the default language's tab the
    # page posts the structure (which fields, their order, types, required,
    # display, choices, destinations, keeping); on another language's tab it
    # posts only that language's texts, and the structure is the stored
    # form's.
    #
    # A field's TYPE is fixed once added (design.md 2.2): a posted type is
    # read only for a row with no stored field behind it.
    #
    # DESTINATIONS (design.md 2.6). The builder draws one section per
    # registered destination type, holding a kind's first stored
    # destination; each is sent with its stored row's id, because
    # `Forms::Save` matches destinations by id only, and one sent without it
    # is a new row that loses its stored secret. A stored destination the
    # builder draws no section for (a second of one kind, which only a
    # script makes, or one of a type no longer registered) is carried as it
    # is stored.
    class Draft
      Row = Data.define(:row, :key, :type, :required, :label, :help, :display, :choices)
      ChoiceRow = Data.define(:row, :key, :label)
      Section = Data.define(:kind, :id, :enabled, :settings, :secrets_set, :secrets_saved_at)

      attr_reader :name, :keep_submissions, :keep_days, :submit_label, :thank_you, :rows, :sections, :carried

      def self.from_form(form)
        new(form: form, name: form.name, keep_submissions: form.keep_submissions, keep_days: form.keep_days,
          submit_label: form.read_attribute(:submit_label).to_h, thank_you: form.read_attribute(:thank_you).to_h,
          rows: form.fields.map { |field| stored_row(field) }, sections: stored_sections(form), carried: carried(form))
      end

      # `posted` is `params[:form]` as a plain Hash (`to_unsafe_h`): every
      # value is read as a String here, and anything of another shape is
      # nothing. `default_tab` says whether the page posted the structure.
      def self.from_params(form, posted, default_tab:)
        posted = plain(posted)
        stored = from_form(form)
        texts = ->(kept, given) { kept.to_h.merge(strings(given)) }
        rows = default_tab ? posted_rows(form, posted) : stored.rows.map { |row| texts_over(row, plain(plain(posted["fields"])[row.row])) }
        new(form: form,
          name: default_tab ? posted["name"].to_s : stored.name,
          keep_submissions: default_tab ? posted["keep_submissions"] == "1" : stored.keep_submissions,
          keep_days: default_tab ? posted["keep_days"].to_s : stored.keep_days,
          submit_label: texts.(stored.submit_label, posted["submit_label"]),
          thank_you: texts.(stored.thank_you, posted["thank_you"]),
          rows: rows,
          sections: default_tab ? posted_sections(form, posted) : stored.sections,
          carried: stored.carried)
      end

      # The secrets typed into the builder, `{ kind => { name => value } }`,
      # only the names each type declares. Never drawn back: a refused save
      # shows the inputs empty again, as the mail login's are.
      def self.posted_secrets(posted)
        plain(plain(posted)["destinations"]).values.each_with_object({}) do |section, secrets|
          section = plain(section)
          type = Forms::DestinationTypes.find(section["kind"].to_s)
          next unless type

          secrets[type.name] = strings(section["secrets"]).slice(*type.secrets)
        end
      end

      def initialize(form:, name:, keep_submissions:, keep_days:, submit_label:, thank_you:, rows:, sections:, carried:)
        @form = form
        @name = name
        @keep_submissions = keep_submissions
        @keep_days = keep_days
        @submit_label = submit_label
        @thank_you = thank_you
        @rows = rows
        @sections = sections
        @carried = carried
      end

      # The section drawn for a destination type (a blank one when the form
      # has none of that kind).
      def section(kind) = sections.find { |section| section.kind == kind } || Section.new(kind: kind, id: nil, enabled: false, settings: {}, secrets_set: [], secrets_saved_at: nil)

      # `Forms::Save`'s three arguments. `secrets` are what the builder
      # posted (a blank one keeps the stored secret of the row named by id).
      def save_arguments(secrets: {})
        attributes = { name: name, keep_submissions: keep_submissions, keep_days: keep_days.presence, submit_label: submit_label, thank_you: thank_you }
        fields = rows.map do |row|
          settings = {}
          settings[:display] = row.display if row.display
          settings[:choices] = row.choices.map { |choice| { key: choice.key, label: choice.label } } if row.choices
          { key: row.key, type: row.type, required: row.required, label: row.label, help: row.help, settings: settings }
        end
        destinations = sections.select(&:enabled).map do |section|
          { id: section.id, kind: section.kind, settings: section.settings, secrets: secrets.fetch(section.kind, {}) }
        end
        { attributes: attributes, fields: fields, destinations: destinations + carried }
      end

      class << self
        private

        def stored_row(field)
          type = Forms::FieldTypes.find(field.type)
          choices = field.choices.map { |choice| ChoiceRow.new(row: choice.key, key: choice.key, label: choice.label) } if type&.options&.include?(:choices)
          Row.new(row: field.key, key: field.key, type: field.type, required: field.required, label: field.label, help: field.help,
            display: (field.settings["display"].presence || Forms::Field::DISPLAYS.first if type&.options&.include?(:display)), choices: choices)
        end

        # A stored row with the posted languages' texts over its own.
        def texts_over(row, posted)
          choices = row.choices&.map do |choice|
            choice.with(label: choice.label.merge(strings(plain(plain(plain(posted["choices"])[choice.row])["label"]))))
          end
          row.with(label: row.label.merge(strings(posted["label"])), help: row.help.merge(strings(posted["help"])), choices: choices)
        end

        def posted_rows(form, posted)
          stored = form.fields.index_by(&:key)
          fields = plain(posted["fields"])
          posted["field_order"].to_s.split.uniq.filter_map do |name|
            given = plain(fields[name])
            next if given.empty?

            kept = stored[given["key"].to_s]
            type_name = kept ? kept.type : given["type"].to_s
            type = Forms::FieldTypes.find(type_name)
            choices = (posted_choices(kept, given) if type&.options&.include?(:choices))
            display = (given["display"].to_s.presence_in(Forms::Field::DISPLAYS) || Forms::Field::DISPLAYS.first if type&.options&.include?(:display))
            Row.new(row: name, key: kept&.key.to_s, type: type_name, required: given["required"] == "1",
              label: (kept&.label || {}).merge(strings(given["label"])), help: (kept&.help || {}).merge(strings(given["help"])),
              display: display, choices: choices)
          end
        end

        def posted_choices(kept, given)
          stored = (kept&.choices || []).index_by(&:key)
          choices = plain(given["choices"])
          given["choice_order"].to_s.split.uniq.filter_map do |name|
            choice = plain(choices[name])
            next if choice.empty?

            existing = stored[choice["key"].to_s]
            ChoiceRow.new(row: name, key: existing&.key.to_s, label: (existing&.label || {}).merge(strings(choice["label"])))
          end
        end

        def stored_sections(form)
          firsts = form.destinations.group_by(&:kind).transform_values(&:first)
          Forms::DestinationTypes.all.filter_map do |type|
            destination = firsts[type.name]
            next unless destination

            Section.new(kind: type.name, id: destination.id, enabled: true, settings: destination.settings.to_h,
              secrets_set: type.secrets.select { |name| destination.secret_set?(name) }, secrets_saved_at: destination.secrets_saved_at)
          end
        end

        # Each registered type's section as posted, its id only when it
        # names a stored row of this form and that kind (`Forms::Save`
        # matches by id and kind as well; this keeps the page from
        # redrawing an id that is no row of this form).
        def posted_sections(form, posted)
          stored = form.destinations.index_by(&:id)
          given = plain(posted["destinations"]).values.map { |section| plain(section) }
          Forms::DestinationTypes.all.map do |type|
            section = given.find { |candidate| candidate["kind"].to_s == type.name } || {}
            row = stored[section["id"].to_s.to_i]
            row = nil unless row&.kind == type.name
            settings = type.fields.to_h { |field| [ field.name, plain(section["settings"])[field.name].to_s ] }.reject { |_, value| value.empty? }
            Section.new(kind: type.name, id: row&.id, enabled: section["enabled"] == "1", settings: settings,
              secrets_set: row ? type.secrets.select { |name| row.secret_set?(name) } : [], secrets_saved_at: row&.secrets_saved_at)
          end
        end

        # A stored destination the builder draws no section for, as stored.
        def carried(form)
          shown = stored_sections(form).map(&:id)
          form.destinations.reject { |destination| shown.include?(destination.id) }.map do |destination|
            { id: destination.id, kind: destination.kind, settings: destination.settings.to_h, secrets: {} }
          end
        end

        # language => text, Strings only; a code is whatever was posted
        # (`Forms::Save` refuses one this CMS does not serve).
        def strings(value) = plain(value).select { |_, text| text.is_a?(String) }.transform_keys(&:to_s)

        def plain(value)
          value = value.to_unsafe_h if value.respond_to?(:to_unsafe_h)
          value.is_a?(Hash) ? value.stringify_keys : {}
        end
      end
    end
  end
end
