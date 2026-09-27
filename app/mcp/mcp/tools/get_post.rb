# Gets a single post by id, including its full body (design spec section 10).
#
# Lives at app/mcp/mcp/tools/get_post.rb -- see the comment atop
# Mcp::ErrorResponse (app/mcp/mcp/error_response.rb) for why the `mcp/`
# directory is nested one level inside the app/mcp autoload root.
module Mcp
  module Tools
    class GetPost < MCP::Tool
      extend Mcp::ErrorResponse

      # Pinned explicitly -- see the comment on CreatePost#tool_name for why
      # the mcp gem's class-name-derived default ("get_post") would otherwise
      # differ from the name clients already call this tool by.
      tool_name "get_post_tool"

      description "Get a single post by id, including its full body. Read in the given locale " \
        "(default: the site's current default locale). The response includes both `published` " \
        "(boolean, kept for compatibility) and `status` (\"draft\", \"scheduled\", or \"live\") -- " \
        "a scheduled post (a future published_at) has published: true but status: \"scheduled\", " \
        "and is not yet visible on the public site."
      input_schema(
        properties: {
          id: { type: "integer" },
          locale: { type: "string", enum: Locales::SUPPORTED.keys }
        },
        required: [ "id" ]
      )
      annotations(read_only_hint: true, idempotent_hint: true, destructive_hint: false, open_world_hint: false,
        title: "Get post")

      def self.call(id:, locale: nil, server_context:)
        post = Post.find_by(id: id)
        return error_response("Post #{id} not found") unless post

        locale ||= Locales.default
        invalid_locale = reject_unless_enabled(locale)
        return invalid_locale if invalid_locale

        data = Mobility.with_locale(locale) { PostSerializer.call(post, locale) }

        MCP::Tool::Response.new([ { type: "text", text: data.to_json } ], structured_content: data)
      end
    end
  end
end
