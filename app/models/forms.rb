# The `Forms::` namespace (docs/reference/forms.md): the form a visitor fills in
# (`Forms::Form`), its fields' types (`Forms::FieldTypes`, the values in
# `app/values/forms/`), where its submissions go (`Forms::DestinationTypes`,
# `Forms::Destination`) and whether the site can keep them
# (`Forms::Encryption`); its writes are `app/services/forms/`. A visitor's
# send is a `Forms::Submission` (its answers encrypted) with one
# `Forms::Delivery` per destination, each delivered by `Forms::DeliveryJob`.
# A name `Admin::Forms` would
# shadow this module (test/lib/admin_namespace_shadow_test.rb): CS Studio's
# components for it live under `Admin::FormsScreen::`.
module Forms
  # How long a submission of a form that keeps nothing waits for a delivery
  # that failed, to be sent again from CS Studio, before it is deleted
  # (`Forms::DeleteSubmissions`, reason `undelivered`).
  UNDELIVERED_DAYS = 30
end
