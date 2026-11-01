module Admin
  module Fields
    # A text input for `:link` fields. Not `type="url"`: a site-relative
    # address ("/about") is a link and no browser URL; `inputmode="url"`
    # keeps the URL keyboard. `ContentModel::FieldTypes.link?` is the real
    # check, on the server.
    class LinkField < Base
    end
  end
end
