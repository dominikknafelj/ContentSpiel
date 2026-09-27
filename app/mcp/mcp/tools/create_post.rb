# Creates a post (design spec section 10), as a thin wrapper around
# Posts::Save (spec §7.3) -- content_type is required and Post.slug is
# auto-generated from title (LocalizedSlug), so the minimum viable call is
# just content_type + title.
#
# Lives at app/mcp/mcp/tools/create_post.rb -- see the comment atop
# Mcp::ErrorResponse (app/mcp/mcp/error_response.rb) for why the `mcp/`
# directory is nested one level inside the app/mcp autoload root.
module Mcp
  module Tools
    class CreatePost < MCP::Tool
      extend Mcp::ErrorResponse

      # Pinned explicitly: the mcp gem derives a tool's default name from its
      # *demodulized* class name (MCP::StringUtils.handle_from_class_name --
      # it drops everything before the last `::` before underscoring), so
      # `Mcp::Tools::CreatePost` would default to "create_post", not
      # "create_post_tool". Clients that already call this tool by its old
      # name must keep working across this internal namespace move.
      tool_name "create_post_tool"

      description "Create a new post. content_type and title are required; everything else is optional. " \
        "Translated fields (title/body/excerpt) are written in the given locale " \
        "(default: the site's current default locale). Defaults to a draft (no published_at) unless " \
        "published: true is given. `fields` holds the content type's own typed fields (open-types " \
        "spec §6), e.g. a resume_entry's company/role_type/start_date/end_date."
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false, open_world_hint: false,
        title: "Create post")

      # `input_schema(...)` (the class macro every other tool uses) sets
      # `@input_schema_value` once, when this file is first loaded -- fine
      # for `Locales::SUPPORTED`, a fixed constant, but `content_type`'s enum
      # has to be `ContentTypes.names` *at read time*, not at load time: the
      # registry is only populated once `to_prepare` runs, and it can grow
      # further afterwards (a plugin, or a test registering a type). The mcp
      # gem itself re-reads this on every `tools/list` and before every call
      # (`MCP::Tool.input_schema_value`/`#input_schema`, see `MCP::Server
      # #call_tool`), so overriding the reader instead of calling the macro
      # is what makes a type registered after boot show up here without a
      # restart.
      def self.input_schema_value
        MCP::Tool::InputSchema.new(
          properties: {
            content_type: { type: "string", enum: ContentTypes.names },
            title: { type: "string" },
            body: { type: "string", description: "HTML." },
            excerpt: { type: "string" },
            fields: { type: "object", description: "The content type's own typed fields, keyed by field name " \
              "(e.g. {\"company\": \"Acme\"} for resume_entry). See each type's field schema." },
            locale: { type: "string", enum: Locales::SUPPORTED.keys },
            published: { type: "boolean" }
          },
          required: [ "content_type", "title" ]
        )
      end

      def self.call(content_type:, title:, body: nil, excerpt: nil, fields: nil, locale: nil, published: false, server_context:)
        locale ||= Locales.default
        invalid_locale = reject_unless_enabled(locale)
        return invalid_locale if invalid_locale

        attributes = { content_type: content_type, published: published }
        translations = { locale => { title: title, body: body, excerpt: excerpt }.compact }

        # Split by the content type's own schema (translated vs. not) rather
        # than handing the whole `fields` hash to both -- a translated key
        # belongs in `translations[locale]`, not in `attributes`, or it would
        # land in the *default* locale regardless of the locale this call
        # actually asked for (Posts::Save assigns `attributes[:fields]` at
        # `Locales.default`; see its own comment).
        if fields
          untranslated, translated = split_fields(content_type, fields)
          attributes[:fields] = untranslated
          translations[locale][:fields] = translated
        end

        result = Posts::Save.call(attributes: attributes, translations: translations)
        return error_response(result.errors.to_sentence) unless result.ok?

        data = Mobility.with_locale(locale) { PostSerializer.call(result.record, locale) }
        MCP::Tool::Response.new([ { type: "text", text: data.to_json } ], structured_content: data)
      end

      # `content_type` may not be registered at all (an unknown type is
      # Posts::Save's own validation error to report, not this tool's), in
      # which case every key is treated as untranslated -- there is no
      # schema to say otherwise, and `fields` will be a no-op on the
      # unregistered type regardless (`Post#assign_fields`).
      def self.split_fields(content_type, fields)
        fields = fields.to_h.symbolize_keys
        translated_names = ContentTypes.find(content_type)&.fields&.select(&:translated?)&.map { |field| field.name.to_sym } || []
        [ fields.except(*translated_names), fields.slice(*translated_names) ]
      end
      private_class_method :split_fields
    end
  end
end
