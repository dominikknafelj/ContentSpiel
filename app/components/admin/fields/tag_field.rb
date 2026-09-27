module Admin
  module Fields
    # A free-text input naming one existing (or new) `Tag`, with a
    # `<datalist>` of existing names for autocomplete (spec §4.3). This is
    # a *schema* `:tag` field -- a single scalar value on a block/post's
    # typed fields, e.g. "which tag is this post list filtered to" -- not
    # `Post`'s own many-to-many `tags`/`tag_names` (spec §5.2's
    # comma-separated tag input on the post editor itself, a different,
    # already-multi-valued concern this component doesn't touch).
    class TagField < Base
      def datalist_id = "#{input_id}-tags"

      def tag_names = Tag.order(:name).pluck(:name)
    end
  end
end
