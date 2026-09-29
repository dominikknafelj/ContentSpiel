module Admin
  # See `Admin::MediaLibrary::GridComponent`'s own class comment for why
  # this namespace is `MediaLibrary`, not `Media`.
  module MediaLibrary
    # One image's detail panel (media library design spec §6): preview,
    # type/size/dimensions, an autosaving title/alt/caption form (`Media
    # ::Save`, alt/caption per locale via the standard language switcher),
    # "Used on" and Delete.
    #
    # `editable?` mirrors `Media::Ownership` (the service this form's own
    # `update` endpoint actually enforces): `media.manage`, or being this
    # asset's own uploader. Unlike a page/post, an asset has no `can_edit?`
    # of its own in `AccessControlHelper` (that method's own case statement
    # only knows `Post`/`Page`) -- ownership isn't a permission `can?` can
    # answer on its own, so this asks it directly rather than trying to
    # force a `Post`/`Page`-shaped question onto a record that isn't
    # either. A viewer this says no to still sees every field, just
    # disabled (`tag.fieldset disabled:`, the same "View only" shape a
    # page/post editor already gives a reader with no edit rights) --
    # never hidden, since they can still read this screen at all (design
    # spec §6: the whole module only ever needs `media.upload`).
    class DetailComponent < Admin::AdminComponent
      ROLE_LABELS = { "hero" => "Hero image", "block_image" => "Image block", "rich_text" => "Rich text" }.freeze

      def initialize(asset:, locale:, url_options: {})
        @asset = asset
        @locale = locale.to_s
        @url_options = url_options
      end

      def editable?
        return @editable if defined?(@editable)

        @editable = can?("media.manage") || (Current.user.present? && asset.created_by_id == Current.user.id)
      end

      def preview_url = asset.src

      def dimensions
        return nil unless asset.width && asset.height

        "#{asset.width} × #{asset.height}px"
      end

      def byte_size = helpers.number_to_human_size(asset.byte_size)

      def status_id = "media-save-status"

      def base_updated_at_id = "media-base-updated-at"

      def base_updated_at_value = asset.updated_at.iso8601(6)

      def form_url = helpers.admin_medium_path(asset, **url_options)

      def form_data
        return {} unless editable?

        {
          controller: "admin--autosave",
          action: "input->admin--autosave#queue change->admin--autosave#queue focusout->admin--autosave#saveNow",
          "admin--autosave-status-id-value": status_id
        }
      end

      def title_value = asset.title

      def title_errors = asset.errors.full_messages_for(:title)

      # Mobility's own per-locale accessor (`locale:`), not the plain
      # reader -- this is the asset's own literal default in the locale
      # being edited, the same "no cross-locale fallback while editing"
      # rule every other translated column's own admin field already
      # follows (`Admin::BlockCardComponent#value_for`'s own comment).
      def alt_value = asset.alt(locale: locale)

      def caption_value = asset.caption(locale: locale)

      def alt_errors = asset.errors.full_messages_for(:alt)

      def caption_errors = asset.errors.full_messages_for(:caption)

      def missing_locales = []

      def language_url
        ->(code) { helpers.admin_medium_path(asset, **(code.to_s == ::Locales.default ? {} : { locale: code })) }
      end

      def index_path = helpers.admin_media_path(**url_options)

      def destroy_path = helpers.admin_medium_path(asset, **url_options)

      def delete_dialog_id = "delete-media-#{asset.id}"

      # Whether Delete is even offered at all -- an asset's own uploader
      # or a `media.manage` holder, same gate as every field above.
      def can_delete? = editable?

      def used? = asset.used?

      # "Used on" (design spec §6): one entry per distinct place, grouped
      # the same way `Media::Asset#usages_summary` already groups its raw
      # `media_usages` rows -- a block's own usage is named by the page or
      # post it sits on (`Media::Destroy#place_of`'s own reasoning: nobody
      # editing this asset cares that a "block_image" row's `owner_type` is
      # technically `ContentBlock`, they care which page shows it). Only
      # an owner the current viewer can actually read
      # (`pages.read`/`posts.read`) becomes a link; unreadable becomes a
      # neutral label (global constraints' own "Used on" ruling) --
      # exactly `Admin::AuditEventsHelper#audit_subject_path`'s rule,
      # reapplied here since neither that helper nor `Media::Destroy`'s own
      # (private, text-only) `#in_use_message` is built to hand back a
      # clickable link.
      def usage_entries
        asset.usages_summary.filter_map do |entry|
          place = place_for(entry[:owner])
          next if place.nil?

          role_label = role_label(entry[:roles])
          locale_suffix = entry[:locales].any? ? " (#{entry[:locales].join(", ")})" : ""
          kind = place.is_a?(Post) ? "post" : "page"

          if can?("#{kind}s.read", place)
            { label: "#{role_label} — #{kind} “#{Audit::Snapshot.label_for(place)}”#{locale_suffix}", path: place_path(place, kind) }
          else
            { label: "#{role_label} — a #{kind} you can't open#{locale_suffix}", path: nil }
          end
        end
      end

      private

      attr_reader :asset, :locale, :url_options

      # A block's own usage is named by its page/post; a page's hero and a
      # post's own rich text are already named by themselves. `nil` for a
      # usage row whose owner no longer exists (a stale index entry --
      # `usages_summary`'s own `includes(:owner)` reads back `nil` there)
      # or an orphaned block with no page/post of its own -- neither is
      # something this panel can name or link to.
      def place_for(owner)
        return nil if owner.nil?

        owner.is_a?(ContentBlock) ? owner.owner : owner
      end

      def place_path(place, kind) = kind == "post" ? helpers.admin_post_path(place, **url_options) : helpers.admin_page_path(place, **url_options)

      # Fix round 1 (review of `0695e7a`): every role this owner's group
      # actually has, not just the first -- `Media::UsageIndex`'s own
      # comment on `#rows_for` is explicit that a single `ContentBlock` can
      # in principle contribute both a `block_image` and a `rich_text` row
      # (nothing there assumes the two only ever come from different block
      # types), so `entry[:roles]` isn't guaranteed to be a single-element
      # Array the way it usually is in practice.
      def role_label(roles) = roles.map { |role| ROLE_LABELS.fetch(role, role) }.join(", ")
    end
  end
end
