# Gets a single post by id, including its full body (design spec section 10).
class GetPostTool < MCP::Tool
  description "Get a single post by id, including its full body. Read in the given locale " \
    "(default: the site's current default locale). The response includes both `published` " \
    "(boolean, kept for compatibility) and `status` (\"draft\", \"scheduled\", or \"live\") -- " \
    "a scheduled post (a future published_at) has published: true but status: \"scheduled\", " \
    "and is not yet visible on the public site."
  input_schema(
    properties: {
      id: { type: "integer" },
      locale: { type: "string", enum: Mobility.available_locales.map(&:to_s) }
    },
    required: [ "id" ]
  )
  annotations(read_only_hint: true, idempotent_hint: true, destructive_hint: false, open_world_hint: false,
    title: "Get post")

  def self.call(id:, locale: nil, server_context:)
    post = Post.find_by(id: id)
    return MCP::Tool::Response.new([ { type: "text", text: "Post #{id} not found" } ], error: true) unless post

    locale ||= Current.site.default_locale
    data = Mobility.with_locale(locale) { PostSerializer.call(post, locale) }

    MCP::Tool::Response.new([ { type: "text", text: data.to_json } ], structured_content: data)
  end
end
