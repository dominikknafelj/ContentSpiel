# The `Forms::` namespace (docs/superpowers/specs/2026-11-03-forms-design.md;
# docs/superpowers/plans/2026-11-03-forms.md): the form a visitor fills in
# (`Forms::Form`), its fields' types (`Forms::FieldTypes`, the values in
# `app/values/forms/`), where its submissions go (`Forms::DestinationTypes`,
# `Forms::Destination`) and whether the site can keep them
# (`Forms::Encryption`); its writes are `app/services/forms/`. Submissions and
# their deliveries come in the plan's Task 3. A name `Admin::Forms` would
# shadow this module (test/lib/admin_namespace_shadow_test.rb): CS Studio's
# components for it live under `Admin::FormsScreen::`.
module Forms
end
