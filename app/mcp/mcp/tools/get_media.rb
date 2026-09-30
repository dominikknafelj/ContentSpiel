# Gets a single library image by id, including where it's used (media
# library design spec §5.2/§6, Task 9) -- an agent choosing an image (or
# deciding whether one is safe to stop using) wants more than the summary
# `list_media_tool` gives.
#
# Lives at app/mcp/mcp/tools/get_media.rb -- see the comment atop
# Mcp::ErrorResponse (app/mcp/mcp/error_response.rb) for why the `mcp/`
# directory is nested one level inside the app/mcp autoload root.
module Mcp
  module Tools
    class GetMedia < MCP::Tool
      extend Mcp::ErrorResponse

      # Pinned explicitly -- see the comment on CreatePost#tool_name for why
      # the mcp gem's class-name-derived default ("get_media") would
      # otherwise differ from the name this tool is actually called by.
      tool_name "get_media_tool"

      description "Get a single library image by id: title, default alt text and caption, dimensions, and every place it's " \
        "currently used. Use its id in a rich-text image directive: " \
        "::image{asset=\"ID\" alt=\"…\" caption=\"…\"}. A `usages` entry is only named (type/id/title) " \
        "when this token can also read that page or post; usages it can't are folded into " \
        "hidden_usages instead, never named. Requires the media.upload permission."
      input_schema(
        properties: {
          id: { type: "integer" },
          locale: { type: "string", enum: Locales::SUPPORTED.keys, description: "Which language's alt text and caption to show (default: the site's current default locale)." }
        },
        required: [ "id" ]
      )
      annotations(read_only_hint: true, idempotent_hint: true, destructive_hint: false, open_world_hint: false,
        title: "Get media")

      def self.call(id:, locale: nil, server_context:)
        # `allowed?`, not `holds?` (final fix wave, M9): `holds?` answers
        # "anywhere, under any scope" for navigation and buttons only
        # (`AccessControl.holds?`'s own comment); an authorization check
        # goes through `allowed?`. `media.upload` is an admin-area key with
        # no record to scope by, so the two answer identically here -- this
        # only keeps the call on the one sanctioned path.
        return permission_denied("media.upload") unless AccessControl.allowed?(Current.actor, "media.upload")

        # No per-asset "read" scope to fold a forbidden id into (unlike
        # `find_readable_post`): the media library has none (`Admin::Media
        # Controller`'s own comment) -- `media.upload`, already checked
        # above, is the whole gate. So a plain `find_by` id lookup is
        # enough; an unknown id is the only "not found" this ever needs --
        # and a trashed image reads as unknown (trash spec §5.1).
        asset = Media::Asset.kept.with_variants.find_by(id: id)
        return image_not_found unless asset

        locale ||= Locales.default
        invalid_locale = reject_unless_enabled(locale)
        return invalid_locale if invalid_locale

        data = data_for(asset, locale)
        MCP::Tool::Response.new([ { type: "text", text: data.to_json } ], structured_content: data)
      end

      def self.data_for(asset, locale)
        places = usage_places(asset)
        readable, hidden = places.partition { |place| AccessControl.allowed?(Current.actor, "#{kind_of(place)}s.read", place) }

        {
          id: asset.id,
          title: asset.title,
          alt: asset.alt_text(override: nil, locale: locale),
          # The default caption (final fix wave, M5), nil when there's none
          # in any language -- what a directive without `caption=` shows.
          caption: asset.caption_text(override: nil, locale: locale),
          width: asset.width,
          height: asset.height,
          usage_count: places.size,
          usages: readable.map { |place| { type: kind_of(place), id: place.id, title: Audit::Snapshot.label_for(place) } },
          hidden_usages: hidden.size
        }
      end
      private_class_method :data_for

      # One entry per distinct place this asset is used -- the same
      # grouping `Media::Asset#usages_summary` already does (one per
      # `(owner_type, owner_id)`, not one per `media_usages` row), resolved
      # from a raw owner (`Page`, `ContentBlock` or `Post`) down to the
      # page/post it's actually shown on, exactly like `Media::Destroy
      # #place_of`/`Admin::MediaLibrary::DetailComponent#place_for`: a
      # block's own usage is named by whichever page or post it sits on,
      # since that -- not the `ContentBlock` row itself -- is what a
      # `pages.read`/`posts.read` grant actually governs. `.uniq` folds
      # together e.g. a page's hero and one of its own image blocks, which
      # would otherwise be two owner groups resolving to the same page.
      # `place_for` drops a stale index entry (an owner already gone) or an
      # orphaned block with no page/post of its own -- neither is
      # something this can name.
      def self.usage_places(asset)
        asset.usages_summary.filter_map { |entry| place_for(entry[:owner]) }.uniq
      end
      private_class_method :usage_places

      def self.place_for(owner)
        return nil if owner.nil?

        owner.is_a?(ContentBlock) ? owner.owner : owner
      end
      private_class_method :place_for

      def self.kind_of(place) = place.is_a?(Post) ? "post" : "page"
      private_class_method :kind_of
    end
  end
end
