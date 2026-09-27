# Updates an existing post (design spec section 10), as a thin wrapper
# around Posts::Save (spec §7.3). Only the fields given are changed -- an
# absent keyword leaves that attribute alone, so a caller updating just the
# body doesn't have to first fetch and resend the title.
class UpdatePostTool < MCP::Tool
  extend McpErrorResponse

  description "Update an existing post. Only the fields given are changed; everything else is left alone. " \
    "Translated fields (title/body/excerpt) are written in the given locale " \
    "(default: the site's current default locale). " \
    "published: true always results in status: \"live\" -- on an already-live post its publish " \
    "date is kept, but on a draft *or a scheduled* post (a future published_at) it is set to now, " \
    "publishing it immediately rather than leaving it scheduled. published: false unpublishes " \
    "back to a draft. The response's `status` field (\"draft\"/\"scheduled\"/\"live\") reflects " \
    "the result; `published` is kept as a boolean for compatibility."
  input_schema(
    properties: {
      id: { type: "integer" },
      title: { type: "string" },
      body: { type: "string", description: "HTML." },
      excerpt: { type: "string" },
      locale: { type: "string", enum: Locales::SUPPORTED.keys },
      published: { type: "boolean", description: "Omit to leave the current publish state alone." }
    },
    required: [ "id" ]
  )
  annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true, open_world_hint: false,
    title: "Update post")

  def self.call(id:, title: nil, body: nil, excerpt: nil, locale: nil, published: nil, server_context:)
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

    result = Posts::Save.call(post, attributes: attributes, translations: translations)
    return error_response(result.errors.to_sentence) unless result.ok?

    data = Mobility.with_locale(locale) { PostSerializer.call(result.record, locale) }
    MCP::Tool::Response.new([ { type: "text", text: data.to_json } ], structured_content: data)
  end
end
