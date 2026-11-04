module Forms
  # A form's one write (forms plan, Task 2; decision 3): its name, its
  # fields, its submit label and thank-you, its keeping and its destinations,
  # saved WHOLE by an explicit Save (a half-typed field is never live, which
  # is what drafts would have given a form). Creating and changing are the
  # same call: `Forms::Save.call(Forms::Form.new, ...)` makes one.
  #
  #   Forms::Save.call(form,
  #     attributes: { name:, keep_submissions:, keep_days:, submit_label: { "en" => "Send" }, thank_you: { ... } },
  #     fields: [ { key:, type:, required:, label: { "en" => "Your name" }, help: { ... },
  #                 settings: { display:, choices: [ { key:, label: { ... } } ] } } ],
  #     destinations: [ { kind: "mail", settings: { recipients: "office@example.com" }, secrets: {} } ])
  #
  # Only the given `attributes` are written (a translated one is a language
  # => text hash, and only its given languages are). `fields` and
  # `destinations` are the whole lists, in order, every call.
  #
  # KEYS. A field's key is what its answers are stored under, so it never
  # changes: a key the form already has is kept, a blank or unknown one (or
  # one given twice) gets `Forms::Field.new_key`. The same for a choice's key
  # within its field. Reordering and relabelling therefore keep every key,
  # and an old submission still reads as it was sent (Review Focus 3).
  #
  # DESTINATIONS are matched to the stored rows by `id` when one is given,
  # else by position and kind, so a stored secret can be kept: a blank
  # secret keeps the stored one (`Forms::Destination#write_secrets!` says
  # how a secret is sealed and written). A stored row nothing matched is
  # deleted.
  #
  # REFUSALS, each a sentence of `config/locales/admin/forms.en.yml`, checked
  # before anything is written (under the form's row lock, so the stored
  # keys a refusal or a kept key reads are the stored ones): a blank or too
  # long name; more than `Form::MAX_FIELDS` fields; a field with no label in
  # the default language; an unknown field type; a choice field with no
  # choices, more than `Form::MAX_CHOICES` or a choice with no label in the
  # default language; an unknown destination or one whose settings its type
  # refuses; a form that neither keeps nor has a destination; keeping
  # without encryption keys (owner's ruling 2); `keep_days` outside
  # `Form::KEEP_DAYS`; a text in a language the site does not have; a
  # trashed form.
  #
  # `forms.manage`, events `form.created` / `form.updated` (the form's own
  # changes, `Audit::Snapshot.field_changes_for`, plus its destinations
  # without their secrets), and `PublicSite.bump_version!` in the
  # transaction when the form's row changed: a form has no published copy,
  # so what a placed form draws is its rows (decision 9). A save that
  # changes nothing records nothing and moves nothing.
  class Save < ApplicationService
    ATTRIBUTES = %i[name keep_submissions keep_days submit_label thank_you].freeze
    TRANSLATED = %i[submit_label thank_you].freeze

    def self.sentence(key, **values) = I18n.t("admin.forms.save.#{key}", **values, raise: true)

    def initialize(form = Form.new, attributes:, fields:, destinations:, actor: Current.actor)
      @form = form
      @attributes = attributes.to_h.symbolize_keys.slice(*ATTRIBUTES)
      @fields = Array(fields).map { |field| field.to_h.deep_stringify_keys }
      @destinations = Array(destinations).map { |destination| destination.to_h.deep_stringify_keys }
      @actor = actor
    end

    def call
      return denied("forms.manage", @form) unless authorize!("forms.manage", @form)
      return failure(@form, [ sentence(:trashed) ]) if @form.trashed?

      created = @form.new_record?
      refusals = []
      saved = Form.transaction(requires_new: true) do
        # The one row this read-modify-writes, locked first and read again:
        # the stored keys a field keeps are the stored row's.
        @form.lock! if @form.persisted?
        before = destination_summary(@form.destinations.to_a)
        refusals = refusals_of(@form.fields)
        raise ActiveRecord::Rollback if refusals.any?

        assign
        unless @form.save
          refusals = @form.errors.full_messages
          raise ActiveRecord::Rollback
        end
        credentials = write_destinations

        changes = Audit::Snapshot.field_changes_for(@form)
        after = destination_summary(@built.map(&:first))
        changes["destinations"] = [ before, after ] if before != after
        # Never a value: whether a destination's credentials were set before
        # and that they are now. The label matches no `filter_parameters`
        # entry, as the mail login's does not.
        changes["Destination credentials"] = credentials if credentials
        record_event(created ? "form.created" : "form.updated", subject: @form, field_changes: changes) if created || changes.any?
        PublicSite.bump_version! if @form.saved_changes.any?
        true
      end
      return refused(refusals) unless saved

      success(@form)
    rescue ActiveRecord::Encryption::Errors::Configuration
      # A secret given on a site without keys. The transaction is rolled back.
      refused([ sentence(:no_encryption_keys_for_secret) ])
    end

    private

    def sentence(key, **values) = self.class.sentence(key, **values)

    # The refusal, with the form's destinations read again: the rows this
    # call matched were assigned what it was given, and the caller's form
    # must not go on showing them as if they were stored.
    def refused(sentences)
      @form.association(:destinations).reset
      failure(@form, sentences)
    end

    def default_language = Locales.name(Locales.default)

    # Every refusal, in the order the form reads, with nothing assigned. As
    # a side effect it builds what is written (`@normalized_fields`,
    # `@built`), so the two cannot disagree.
    def refusals_of(stored_fields)
      refusals = []
      refusals << sentence(:trashed) if @form.trashed?
      refusals.concat(name_refusals)
      refusals.concat(language_refusals)
      refusals.concat(field_refusals(stored_fields))
      refusals.concat(destination_refusals)
      refusals.concat(keeping_refusals)
      refusals
    end

    def name_refusals
      name = (@attributes.key?(:name) ? @attributes[:name] : @form.name).to_s.strip
      return [ sentence(:name_blank) ] if name.empty?
      return [ sentence(:name_too_long, count: Form::NAME_MAX) ] if name.length > Form::NAME_MAX

      []
    end

    # The languages every text is given in must be the site's: a text under
    # another would be kept and never shown.
    def language_refusals
      given = TRANSLATED.flat_map { |name| @attributes[name].to_h.keys }
      given += @fields.flat_map do |field|
        field["label"].to_h.keys + field["help"].to_h.keys +
          Array(field.dig("settings", "choices")).flat_map { |choice| choice.to_h.fetch("label", {}).to_h.keys }
      end
      unknown = given.map(&:to_s).uniq - Locales.enabled.map(&:to_s)
      unknown.empty? ? [] : [ sentence(:unknown_languages, codes: unknown.join(", ")) ]
    end

    def field_refusals(stored_fields)
      return [ sentence(:too_many_fields, count: Form::MAX_FIELDS) ] if @fields.size > Form::MAX_FIELDS

      stored = stored_fields.index_by(&:key)
      used = Set.new
      refusals = []
      @normalized_fields = @fields.each_with_index.map do |input, index|
        type = FieldTypes.find(input["type"])
        label = texts(input["label"])
        name = label[Locales.default] || sentence(:field_at, position: index + 1)
        refusals << sentence(:unknown_field_type, type: input["type"].to_s) unless type
        refusals << sentence(:label_missing, position: index + 1, language: default_language) unless label.key?(Locales.default)

        key = kept_key(input["key"], stored.keys, used) { Field.new_key }
        settings = type ? field_settings(type, input, stored[key], name, refusals) : {}
        { "key" => key, "type" => input["type"].to_s, "required" => ActiveModel::Type::Boolean.new.cast(input["required"]) == true,
          "label" => label, "help" => texts(input["help"]), "settings" => settings }
      end
      refusals
    end

    # A choice field's display and choices, the only settings a built-in
    # type has (`FieldType#options`); a type that offers neither has none.
    def field_settings(type, input, stored_field, name, refusals)
      settings = {}
      if type.options.include?(:display)
        display = input.dig("settings", "display").to_s
        settings["display"] = Field::DISPLAYS.include?(display) ? display : Field::DISPLAYS.first
      end
      return settings unless type.options.include?(:choices)

      choices = Array(input.dig("settings", "choices")).map { |choice| choice.to_h.stringify_keys }
      if choices.empty?
        refusals << sentence(:choices_missing, field: name)
      elsif choices.size > Form::MAX_CHOICES
        refusals << sentence(:too_many_choices, field: name, count: Form::MAX_CHOICES)
      end
      stored_keys = stored_field ? stored_field.choices.map(&:key) : []
      used = Set.new
      settings["choices"] = choices.map do |choice|
        label = texts(choice["label"])
        { "key" => kept_key(choice["key"], stored_keys, used) { Choice.new_key }, "label" => label }
      end
      if settings["choices"].any? { |choice| !choice["label"].key?(Locales.default) }
        refusals << sentence(:choice_label_missing, field: name, language: default_language)
      end
      settings
    end

    # A key the stored list has, given once, is kept; anything else is a new
    # one (the block makes it).
    def kept_key(given, stored_keys, used)
      key = given.to_s
      key = yield unless stored_keys.include?(key) && !used.include?(key)
      used << key
      key
    end

    # A language => text hash, the texts stripped and a blank one dropped.
    def texts(hash) = hash.to_h.to_h { |locale, text| [ locale.to_s, text.to_s.strip ] }.reject { |_, text| text.empty? }

    # Each given destination matched to a stored row or built anew, with its
    # settings assigned, and the sentences its type refuses them with.
    def destination_refusals
      existing = @form.persisted? ? @form.destinations.to_a : []
      taken = Set.new
      @built = @destinations.each_with_index.map do |input, index|
        destination = matched(existing, input, index, taken) || Destination.new(form: @form)
        taken << destination.id if destination.persisted?
        type = DestinationTypes.find(input["kind"])
        destination.assign_attributes(kind: input["kind"].to_s, position: index, settings: settings_of(type, input["settings"]))
        secrets = type ? input["secrets"].to_h.slice(*type.secrets).transform_values(&:to_s).reject { |_, value| value.strip.empty? } : {}
        [ destination, secrets ]
      end
      @removed = existing.reject { |destination| taken.include?(destination.id) }
      @built.flat_map { |destination, _| destination.valid? ? [] : destination.errors[:base] }.uniq
    end

    def matched(existing, input, index, taken)
      found = existing.find { |destination| destination.id == input["id"].to_i } if input["id"].present?
      found ||= existing[index] if existing[index]&.kind == input["kind"].to_s
      found unless found.nil? || taken.include?(found.id)
    end

    # The type's own fields, each cast by its field type, a blank one left
    # out; nothing the type does not declare is kept.
    def settings_of(type, given)
      return {} unless type

      given = given.to_h.stringify_keys
      type.fields.each_with_object({}) do |field, settings|
        raw = given[field.name]
        next if raw.nil? || raw.to_s.strip.empty?

        settings[field.name] = field.field_type.cast.call(raw)
      end
    end

    def keeping_refusals
      keep = keeping?
      refusals = []
      if @attributes.key?(:keep_days) && @attributes[:keep_days].to_s.strip.present? && keep_days.nil?
        refusals << sentence(:keep_days, min: Form::KEEP_DAYS.min, max: Form::KEEP_DAYS.max)
      end
      refusals << sentence(:no_encryption_keys) if keep && !Encryption.available?
      refusals << sentence(:nowhere) if !keep && @destinations.empty?
      refusals
    end

    def keeping? = @attributes.key?(:keep_submissions) ? ActiveModel::Type::Boolean.new.cast(@attributes[:keep_submissions]) == true : @form.keep_submissions

    # The given days as an Integer in `Form::KEEP_DAYS`, else nil (blank:
    # the site's default; anything else is refused by `keeping_refusals`).
    def keep_days
      value = @attributes[:keep_days]
      days = value.is_a?(Integer) ? value : Integer(value.to_s.strip, 10, exception: false)
      days if days && Form::KEEP_DAYS.cover?(days)
    end

    def assign
      @form.name = @attributes[:name].to_s.strip if @attributes.key?(:name)
      @form.keep_submissions = keeping?
      @form.keep_days = keep_days if @attributes.key?(:keep_days)
      @form.fields = @normalized_fields
      TRANSLATED.each do |attribute|
        next unless @attributes.key?(attribute)

        @attributes[attribute].to_h.each do |locale, text|
          Mobility.with_locale(locale) { @form.public_send(:"#{attribute}=", text.to_s.strip.presence) }
        end
      end
    end

    # The rows written in the given order; a row nothing matched deleted.
    # Returns the credentials' change for the audit row, or nil when no
    # secret was written.
    def write_destinations
      Destination.where(id: @removed.map(&:id)).delete_all if @removed.any? # version: none (a destination is on no public page)
      written = false
      were_set = false
      @built.each do |destination, secrets|
        destination.save!
        next if secrets.empty?

        were_set ||= destination.destination_type.secrets.any? { |name| destination.secret_set?(name) }
        destination.write_secrets!(secrets)
        written = true
      end
      [ were_set ? "set" : "not set", "set" ] if written
    end

    # What the audit row says of a form's destinations: their kinds, their
    # settings and which secrets are set, never a secret's value.
    def destination_summary(destinations)
      destinations.map do |destination|
        names = destination.destination_type&.secrets.to_a.select { |name| destination.secret_set?(name) }
        { "kind" => destination.kind, "settings" => destination.settings.deep_dup, "secrets_set" => names }
      end
    end
  end
end
