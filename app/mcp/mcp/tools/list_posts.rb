# Lists posts, optionally filtered by content type (design spec section
# 10). A summary view, not the full record -- see PostListSerializer.
#
# Lives at app/mcp/mcp/tools/list_posts.rb -- see the comment atop
# Mcp::ErrorResponse (app/mcp/mcp/error_response.rb) for why the `mcp/`
# directory is nested one level inside the app/mcp autoload root.
module Mcp
  module Tools
    class ListPosts < MCP::Tool
      extend Mcp::ErrorResponse

      # Pinned explicitly -- see the comment on CreatePost#tool_name for why
      # the mcp gem's class-name-derived default ("list_posts") would
      # otherwise differ from the name clients already call this tool by.
      tool_name "list_posts_tool"

      description "List posts, optionally filtered by content type. Titles/slugs/excerpts are read in the given locale " \
        "(default: the site's current default locale)."
      input_schema(
        properties: {
          content_type: { type: "string", enum: Post.content_types.keys, description: "Only list posts of this type." },
          locale: { type: "string", enum: Locales::SUPPORTED.keys }
        }
      )
      annotations(read_only_hint: true, idempotent_hint: true, destructive_hint: false, open_world_hint: false,
        title: "List posts")

      def self.call(content_type: nil, locale: nil, server_context:)
        locale ||= Locales.default
        invalid_locale = reject_unless_enabled(locale)
        return invalid_locale if invalid_locale

        scope = content_type.present? ? Post.where(content_type: content_type) : Post.all

        # A summary, not the full record: a body-per-post dump would bloat every
        # listing for content an agent can ask for individually via Mcp::Tools::GetPost.
        posts = Mobility.with_locale(locale) do
          scope.order(:id).map { |post| PostSerializer.call(post, locale).except(:body) }
        end

        MCP::Tool::Response.new([ { type: "text", text: posts.to_json } ], structured_content: posts)
      end
    end
  end
end
