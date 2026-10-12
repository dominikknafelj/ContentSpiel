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
        "(default: the site's current default locale), without falling back -- a locale with no " \
        "body of its own returns an empty string. `body` is Markdown in the same format " \
        "create_post_tool/update_post_tool accept: embeds are directives on their own line " \
        "(::youtube{id=\"…\"}, ::image{asset=\"42\" alt=\"…\" caption=\"…\"}) and links to this " \
        "site's own pages/posts are [text](cs:page/<id>) / [text](cs:post/<id>). The response includes both `published` " \
        "(boolean, kept for compatibility) and `status` (\"draft\", \"scheduled\", or \"live\") -- " \
        "a scheduled post (a future published_at) has published: true but status: \"scheduled\", " \
        "and is not yet visible on the public site. `unpublished_changes` is true when a live or scheduled " \
        "post has edits the site does not show yet: what this tool returns is the working version."
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
        post = find_readable_post(id)
        return post_not_found unless post

        locale ||= Locales.default
        invalid_locale = reject_unless_enabled(locale)
        return invalid_locale if invalid_locale

        data = Mobility.with_locale(locale) { PostSerializer.call(post, locale) }

        MCP::Tool::Response.new([ { type: "text", text: data.to_json } ], structured_content: data)
      end
    end
  end
end
