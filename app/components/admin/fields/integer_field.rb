module Admin
  module Fields
    # A number input (spec §4.3), for `:integer` fields -- `min`/`max`
    # render as the matching HTML attributes (browser-level guardrails
    # only; `ContentModel::FieldSet#validate_fields` is the real check).
    class IntegerField < Base
    end
  end
end
