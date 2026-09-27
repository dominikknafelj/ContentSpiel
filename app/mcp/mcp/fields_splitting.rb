# Shared by CreatePost and UpdatePost: splitting a tool's `fields:` argument
# into the content type's untranslated and translated keys before handing
# them to `Posts::Save` (open-types spec §6) -- a translated key belongs in
# `translations[locale]`, not `attributes`, or it would land in the *default*
# locale regardless of which locale the call actually asked for
# (`Posts::Save` assigns `attributes[:fields]` at `Locales.default`; see its
# own comment). `extend`ed (not `include`d), same reasoning as
# `Mcp::ErrorResponse`: every tool's `.call` is itself a class method.
#
# Lives at app/mcp/mcp/fields_splitting.rb, not app/mcp/fields_splitting.rb --
# see the comment atop Mcp::ErrorResponse for why the `mcp/` directory is
# nested one level inside the app/mcp autoload root.
module Mcp
  module FieldsSplitting
    # `content_type` may not be registered at all (an unknown type is
    # Posts::Save's own validation error to report, not a tool's), in which
    # case every key is treated as untranslated -- there is no schema to say
    # otherwise, and `fields` will be a no-op on the unregistered type
    # regardless (`Post#assign_fields`).
    def split_fields(content_type, fields)
      fields = fields.to_h.symbolize_keys
      translated_names = ContentTypes.find(content_type)&.fields&.select(&:translated?)&.map { |field| field.name.to_sym } || []
      [ fields.except(*translated_names), fields.slice(*translated_names) ]
    end
  end
end
