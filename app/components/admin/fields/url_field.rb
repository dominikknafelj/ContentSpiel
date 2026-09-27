module Admin
  module Fields
    # A `type="url"` input (spec §4.3), for `:url` fields -- the browser's
    # own URL keyboard/validation hint; `FieldSet#url?` is the real check.
    class UrlField < Base
    end
  end
end
