module Admin
  module Fields
    # A multi-line `<textarea>` (spec §4.3), for `:text` fields -- longer
    # free text that isn't rich (that's the `rich_text` column type,
    # `Admin::Columns::RichTextColumnComponent`).
    class TextField < Base
    end
  end
end
