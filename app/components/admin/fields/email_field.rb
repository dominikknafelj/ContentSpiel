module Admin
  module Fields
    # A `type="email"` input, for `:email` fields -- the browser's own
    # address keyboard and hint; `ContentModel::FieldTypes`' `:email` is the
    # real check (one plain address, at most 254 characters).
    class EmailField < Base
    end
  end
end
