# Updates an existing post (design spec section 10). Only the fields given
# are changed -- an absent keyword leaves that attribute alone, so a caller
# updating just the body doesn't have to first fetch and resend the title.
class UpdatePostTool < MCP::Tool
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
      locale: { type: "string", enum: Mobility.available_locales.map(&:to_s) },
      published: { type: "boolean", description: "Omit to leave the current publish state alone." }
    },
    required: [ "id" ]
  )
  annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true, open_world_hint: false,
    title: "Update post")

  def self.call(id:, title: nil, body: nil, excerpt: nil, locale: nil, published: nil, server_context:)
    post = Post.find_by(id: id)
    return MCP::Tool::Response.new([ { type: "text", text: "Post #{id} not found" } ], error: true) unless post

    locale ||= SiteSetting.instance.default_locale
    translated_attrs = { title: title, body: body, excerpt: excerpt }.compact

    # Build all attributes to assign, handling published_at carefully:
    # - If published is omitted (nil), leave published_at alone
    # - If published: false, set published_at to nil
    # - If published: true on a live post, keep existing published_at
    # - If published: true on a draft/scheduled post, set to now
    attrs_to_assign = translated_attrs.dup
    unless published.nil?
      attrs_to_assign[:published_at] = if published
        post.live? ? post.published_at : Time.current
      else
        nil
      end
    end

    # Assign all attributes and save atomically within the locale context,
    # so if any validation fails, nothing is written to the database.
    Mobility.with_locale(locale) do
      post.assign_attributes(attrs_to_assign)
      post.save!
    end

    data = Mobility.with_locale(locale) { PostSerializer.call(post, locale) }
    MCP::Tool::Response.new([ { type: "text", text: data.to_json } ], structured_content: data)
  rescue ActiveRecord::RecordInvalid => e
    MCP::Tool::Response.new([ { type: "text", text: e.message } ], error: true)
  end
end
