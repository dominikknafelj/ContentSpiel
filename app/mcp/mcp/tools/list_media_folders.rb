# Lists the media library's folders in the tree's order (a folder before its
# children, siblings in natural order), each with its path and the number of
# kept images directly in it, so an agent can choose the `folder` for
# `list_media_tool`.
#
# Lives at app/mcp/mcp/tools/list_media_folders.rb -- see the comment atop
# Mcp::ErrorResponse (app/mcp/mcp/error_response.rb) for why the `mcp/`
# directory is nested one level inside the app/mcp autoload root.
module Mcp
  module Tools
    class ListMediaFolders < MCP::Tool
      extend Mcp::ErrorResponse

      # Pinned explicitly -- see the comment on CreatePost#tool_name.
      tool_name "list_media_folders_tool"

      description "List the media library's folders in tree order. Each has an `id` (for list_media_tool's " \
        "`folder`), its `name`, its `parent_id` (null for a top folder), its `path` (\"Clients / Acme\") and " \
        "`image_count`, the images directly in it (subfolders' not included, trashed ones never). Requires " \
        "the media.upload permission."
      input_schema(properties: {})
      annotations(read_only_hint: true, idempotent_hint: true, destructive_hint: false, open_world_hint: false,
        title: "List media folders")

      def self.call(server_context:)
        return permission_denied("media.upload") unless AccessControl.allowed?(Current.actor, "media.upload")

        tree = Media::FolderTree.load
        counts = Media::FolderCounts.call.fetch(:folders)
        items = tree.each_in_order.map do |node, _depth|
          { id: node.id, name: node.name, parent_id: node.parent_id, path: tree.path_name(node.id),
            image_count: counts.fetch(node.id, 0) }
        end

        MCP::Tool::Response.new([ { type: "text", text: items.to_json } ], structured_content: items)
      end
    end
  end
end
