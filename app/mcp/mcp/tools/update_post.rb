# Updates an existing post (design spec section 10), as a thin wrapper
# around Posts::Save (spec §7.3). Only the fields given are changed -- an
# absent keyword leaves that attribute alone, so a caller updating just the
# body doesn't have to first fetch and resend the title.
#
# Lives at app/mcp/mcp/tools/update_post.rb -- see the comment atop
# Mcp::ErrorResponse (app/mcp/mcp/error_response.rb) for why the `mcp/`
# directory is nested one level inside the app/mcp autoload root.
module Mcp
  module Tools
    class UpdatePost < MCP::Tool
      extend Mcp::ErrorResponse

      # Pinned explicitly -- see the comment on CreatePost#tool_name for why
      # the mcp gem's class-name-derived default ("update_post") would
      # otherwise differ from the name clients already call this tool by.
      tool_name "update_post_tool"

      description "Update an existing post. Only the fields given are changed; everything else is left alone. " \
        "Translated fields (title/body/excerpt) are written in the given locale " \
        "(default: the site's current default locale). " \
        "published: true always results in status: \"live\" -- on an already-live post its publish " \
        "date is kept, but on a draft *or a scheduled* post (a future published_at) it is set to now, " \
        "publishing it immediately rather than leaving it scheduled. published: false unpublishes " \
        "back to a draft. The response's `status` field (\"draft\"/\"scheduled\"/\"live\") reflects " \
        "the result; `published` is kept as a boolean for compatibility. `fields` holds the post's " \
        "own content type's typed fields (open-types spec §6); it can't change content_type itself."
      input_schema(
        properties: {
          id: { type: "integer" },
          title: { type: "string" },
          body: { type: "string", description: "HTML." },
          excerpt: { type: "string" },
          fields: { type: "object", description: "The content type's own typed fields, keyed by field name " \
            "(e.g. {\"company\": \"Acme\"} for resume_entry). See each type's field schema." },
          locale: { type: "string", enum: Locales::SUPPORTED.keys },
          published: { type: "boolean", description: "Omit to leave the current publish state alone." }
        },
        required: [ "id" ]
      )
      annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true, open_world_hint: false,
        title: "Update post")

      def self.call(id:, title: nil, body: nil, excerpt: nil, fields: nil, locale: nil, published: nil, server_context:)
        post = Post.find_by(id: id)
        return error_response("Post #{id} not found") unless post

        locale ||= Locales.default
        invalid_locale = reject_unless_enabled(locale)
        return invalid_locale if invalid_locale

        # `published:` is only added to `attributes:` when given at all --
        # `Posts::Save`'s own publish rule treats `nil` there as "leave alone",
        # `false` as "unpublish", the same three-way distinction this tool has
        # always made, just delegated now instead of hand-rolled per call.
        attributes = published.nil? ? {} : { published: published }
        translations = { locale => { title: title, body: body, excerpt: excerpt }.compact }

        # Split against the post's own (already-persisted) content type --
        # unlike CreatePost there's no candidate `content_type` argument to
        # read this off of, and this tool can't change it anyway.
        if fields
          untranslated, translated = split_fields(post.content_type, fields)
          attributes[:fields] = untranslated
          translations[locale][:fields] = translated
        end

        result = Posts::Save.call(post, attributes: attributes, translations: translations)
        return error_response(result.errors.to_sentence) unless result.ok?

        data = Mobility.with_locale(locale) { PostSerializer.call(result.record, locale) }
        MCP::Tool::Response.new([ { type: "text", text: data.to_json } ], structured_content: data)
      end

      # See the identical helper on CreatePost -- kept as its own copy rather
      # than called cross-class since `private_class_method` (there and here)
      # can't be invoked with an explicit receiver from outside its own class.
      def self.split_fields(content_type, fields)
        fields = fields.to_h.symbolize_keys
        translated_names = ContentTypes.find(content_type)&.fields&.select(&:translated?)&.map { |field| field.name.to_sym } || []
        [ fields.except(*translated_names), fields.slice(*translated_names) ]
      end
      private_class_method :split_fields
    end
  end
end
