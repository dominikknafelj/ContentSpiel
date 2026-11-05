module Forms
  # One kind of destination a form's submissions go to, as
  # `Forms::DestinationTypes` holds it:
  #
  # - `name`: `"mail"` for the built-in, `"owner/name"` for a gem's
  #   (`ContentSpiel::Plugins.form_destinations`).
  # - `label`: the builder's word for it, a literal as a block type's.
  # - `fields`: its settings, `ContentModel::Definition::Field`s declared
  #   against `ContentModel::FieldTypes` (so CS Studio draws them with
  #   `Admin::Ui::FieldComponent`, the inputs every content field has), stored
  #   per destination in `form_destinations.settings`.
  # - `secrets`: the names of the settings that are credentials, stored
  #   sealed and never shown again (`Forms::Destination#write_secrets!`).
  # - `deliverer`: what delivers one submission, from a job:
  #   `deliverer.deliver(delivery, final_attempt:)` answers nil when it was
  #   delivered, raises `Forms::DestinationTypes::Retry` for a failure worth
  #   another attempt and `Forms::DestinationTypes::Failed.new(key:, line:)`
  #   for one that is final. A deliverer MAY also answer
  #   `settings_errors(settings)` (sentences about settings its fields' types
  #   cannot judge, the mail's list of addresses) and `recipients(settings)`
  #   (the addresses a destination is sent to, for the screens).
  DestinationType = Data.define(:name, :label, :fields, :secrets, :deliverer)
end
