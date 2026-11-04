module Forms
  # One place a form's submissions go (forms spec, "Destinations"): a kind
  # (`Forms::DestinationTypes`), its settings, and its secrets. Written only
  # by `Forms::Save`, which replaces a form's list whole.
  #
  # SETTINGS are the type's fields' values, cast and validated by the
  # content model's field types (`ContentModel::FieldTypes`), plus whatever
  # the deliverer says of them (`settings_errors`: the mail's addresses).
  #
  # SECRETS are written once and never shown again, as the mail login is
  # (`Settings::Save#write_mail_login`): with `update_columns`, straight to
  # the column, never decrypting what is stored. Each is SEALED ON ITS OWN
  # with Active Record encryption (`ActiveRecord::Encryption.encryptor`, the
  # site's keys) and the column holds `{ name => ciphertext }`, so:
  #
  # - whether a secret is set is read off the stored ciphertext's presence
  #   (`#secret_set?`), with no key, which a screen asks to say "Set";
  # - replacing one secret leaves the others' ciphertext as it was, so no
  #   save ever decrypts (a secret the current keys can no longer read can
  #   still be replaced, the reason the mail login is written this way);
  # - a blank secret keeps the stored one (`Forms::Save`).
  #
  # Only the deliverer reads a secret's value (`#secret`, Task 3), in a job.
  # A secret's name is no secret; its value never reaches an audit snapshot
  # (`Audit::Snapshot` names a form's destinations without it, and
  # `secrets` is in `NEVER_STORED`), a log line or a page.
  class Destination < ApplicationRecord
    self.table_name = "form_destinations"

    belongs_to :form, class_name: "Forms::Form", inverse_of: :destinations

    serialize :secrets, coder: JSON, type: Hash

    validates :kind, presence: true
    validate :settings_follow_their_type

    def destination_type = DestinationTypes.find(kind)

    # The addresses it is sent to, for a type that has them (the mail's
    # parsed list), else none.
    def recipients
      deliverer = destination_type&.deliverer
      deliverer.respond_to?(:recipients) ? deliverer.recipients(settings) : []
    end

    def secret_set?(name) = secrets.to_h[name.to_s].present?

    # The secret's value, decrypted (a deliverer's, in a job), or nil.
    def secret(name)
      sealed = secrets.to_h[name.to_s]
      sealed.presence && ActiveRecord::Encryption.encryptor.decrypt(sealed)
    end

    # Seals each given value and writes it beside the others, with no
    # callback (`update_columns`), in the caller's transaction. `values` holds
    # only non-blank secrets of the type; nothing stored is read but the
    # other names' ciphertext. Raises `ActiveRecord::Encryption::Errors
    # ::Configuration` on a site without keys (`Forms::Save` says so).
    def write_secrets!(values)
      return if values.empty?

      sealed = values.to_h { |name, value| [ name.to_s, ActiveRecord::Encryption.encryptor.encrypt(value.to_s) ] }
      update_columns(secrets: secrets.to_h.merge(sealed), secrets_saved_at: Time.current) # version: none (a destination's secret is on no public page)
    end

    private

    # Each field of the type: blank when required is refused, a value its
    # type refuses is refused, then the deliverer's own sentences. Errors are
    # whole sentences on `:base` (`Forms::Save` hands them on as they are).
    def settings_follow_their_type
      type = destination_type
      return errors.add(:base, I18n.t("admin.forms.save.unknown_destination", kind: kind)) unless type

      values = settings.to_h.stringify_keys
      scratch = ActiveModel::Errors.new(self)
      type.fields.each do |field|
        raw = values[field.name]
        value = raw.respond_to?(:empty?) && raw.to_s.strip.empty? ? nil : raw
        value = field.field_type.cast.call(value) unless value.nil?
        if value.nil?
          errors.add(:base, I18n.t("admin.forms.destinations.blank", field: field.label)) if field.required?
          next
        end
        field.field_type.validate.call(field: field, value: value, raw: raw, errors: scratch, stored: nil, translations: {})
      end
      scratch.each { |error| errors.add(:base, "#{error.full_message}.") }
      deliverer = type.deliverer
      deliverer.settings_errors(values).each { |sentence| errors.add(:base, sentence) } if deliverer.respond_to?(:settings_errors)
    end
  end
end
