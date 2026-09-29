# Lists library images (media library design spec §6/§5.2, Task 9),
# searchable the same way the CS Studio grid is and filterable to unused
# ones -- a summary view, one page at a time, so an agent can find an id to
# reference from a rich-text ::image{} directive without dumping the whole
# library.
#
# Lives at app/mcp/mcp/tools/list_media.rb -- see the comment atop
# Mcp::ErrorResponse (app/mcp/mcp/error_response.rb) for why the `mcp/`
# directory is nested one level inside the app/mcp autoload root.
module Mcp
  module Tools
    class ListMedia < MCP::Tool
      extend Mcp::ErrorResponse

      # Pinned explicitly -- see the comment on CreatePost#tool_name for why
      # the mcp gem's class-name-derived default ("list_media") would
      # otherwise differ from the name this tool is actually called by.
      tool_name "list_media_tool"

      # At most this many assets per call (ruling: "at most 50 per call
      # with a simple page: param") -- the same order of magnitude as the
      # CS Studio grid's own PER_PAGE (Admin::MediaController), just a
      # round number rather than "about 48".
      PER_PAGE = 50

      description "List images in the media library, newest first. `query` matches title, alt text (any " \
        "language) or the original filename; `unused` narrows to images nothing currently references. " \
        "Each result's `directive` is a ready-to-paste ::image{asset=\"ID\"} for a post/page rich-text " \
        "body -- add alt/caption yourself, e.g. ::image{asset=\"42\" alt=\"…\" caption=\"…\"}. Requires " \
        "the media.upload permission."
      input_schema(
        properties: {
          query: { type: "string", description: "Matches title, alt text (any language), or filename." },
          unused: { type: "boolean", description: "Only images with no usages anywhere on the site." },
          locale: { type: "string", enum: Locales::SUPPORTED.keys, description: "Which language's alt text to show (default: the site's current default locale)." },
          page: { type: "integer", description: "1-indexed; up to 50 results per page (default: 1)." }
        }
      )
      annotations(read_only_hint: true, idempotent_hint: true, destructive_hint: false, open_world_hint: false,
        title: "List media")

      def self.call(query: nil, unused: false, locale: nil, page: 1, server_context:)
        # `allowed?`, not `holds?` (final fix wave, M9): `holds?` answers
        # "anywhere, under any scope" for navigation and buttons only
        # (`AccessControl.holds?`'s own comment); an authorization check
        # goes through `allowed?`. `media.upload` is an admin-area key with
        # no record to scope by, so the two answer identically here -- this
        # only keeps the call on the one sanctioned path.
        return permission_denied("media.upload") unless AccessControl.allowed?(Current.actor, "media.upload")

        locale ||= Locales.default
        invalid_locale = reject_unless_enabled(locale)
        return invalid_locale if invalid_locale

        scope = Media::Asset.with_variants
        scope = scope.unused if unused
        scope = Media::Search.call(scope, query) if query.present?

        page_number = [ page.to_i, 1 ].max
        assets = scope.order(id: :desc).offset((page_number - 1) * PER_PAGE).limit(PER_PAGE).to_a
        counts = usage_counts(assets)

        items = assets.map { |asset| entry_for(asset, locale, counts) }

        MCP::Tool::Response.new([ { type: "text", text: items.to_json } ], structured_content: items)
      end

      # One query for every asset on this page, not one per asset --
      # `Media::Usage` has no counter cache (design spec §3.2: it's a fully
      # derived index, rebuilt wholesale by `Media::UsageIndex`, not a
      # column any owner's save keeps in sync), so this is the plain
      # `GROUP BY` a listing needs instead, computed once for the whole
      # page and handed to `entry_for` per asset rather than queried again
      # per asset.
      def self.usage_counts(assets)
        Media::Usage.where(media_asset_id: assets.map(&:id)).group(:media_asset_id).count
      end
      private_class_method :usage_counts

      def self.entry_for(asset, locale, counts)
        {
          id: asset.id,
          title: asset.title,
          # `alt_text(override: nil, ...)` -- no placement override to
          # apply here, just this asset's own default in `locale`, falling
          # back the same way every other translated reader in this app
          # does (`Media::Asset#alt_text`'s own comment).
          alt: asset.alt_text(override: nil, locale: locale),
          width: asset.width,
          height: asset.height,
          usage_count: counts.fetch(asset.id, 0),
          directive: %(::image{asset="#{asset.id}"})
        }
      end
      private_class_method :entry_for
    end
  end
end
