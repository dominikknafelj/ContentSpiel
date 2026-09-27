# Creates a post (design spec section 10). content_type is required and
# Post.slug is auto-generated from title (LocalizedSlug), so the minimum
# viable call is just content_type + title.
class CreatePostTool < MCP::Tool
  description "Create a new post. content_type and title are required; everything else is optional. " \
    "Translated fields (title/body/excerpt) are written in the given locale " \
    "(default: the site's current default locale). Defaults to a draft (no published_at) unless " \
    "published: true is given."
  input_schema(
    properties: {
      content_type: { type: "string", enum: Post.content_types.keys },
      title: { type: "string" },
      body: { type: "string", description: "HTML." },
      excerpt: { type: "string" },
      locale: { type: "string", enum: Mobility.available_locales.map(&:to_s) },
      published: { type: "boolean" }
    },
    required: [ "content_type", "title" ]
  )
  annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false, open_world_hint: false,
    title: "Create post")

  def self.call(content_type:, title:, body: nil, excerpt: nil, locale: nil, published: false, server_context:)
    locale ||= Current.site.default_locale

    post = Mobility.with_locale(locale) do
      Post.create!(
        content_type: content_type,
        title: title,
        body: body,
        excerpt: excerpt,
        published_at: published ? Time.current : nil
      )
    end

    data = Mobility.with_locale(locale) { PostSerializer.call(post, locale) }
    MCP::Tool::Response.new([ { type: "text", text: data.to_json } ], structured_content: data)
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    MCP::Tool::Response.new([ { type: "text", text: e.message } ], error: true)
  end
end
