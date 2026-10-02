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

      # `notice:`/`alert:` are the flash a restore-via-Undo redirect
      # (`Admin::TrashController#restore`, Task 10) or a failed delete's own
      # `alert:` (`Admin::MediaController#destroy`) leaves for this panel to
      # show -- the same "the controller's flash, read by the view, handed
      # to the component" shape `Admin::RecordHeaderComponent`/`Admin::
      # PostFormComponent` already use for a page/post.
      def initialize(asset:, locale:, url_options: {}, notice: nil, alert: nil)
        @asset = asset
        @locale = locale.to_s
        @url_options = url_options
        @notice = notice
        @alert = alert
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

      # The default-language alt/caption, shown read-only beside the field
      # in another language (as every other translated field's original
      # is) -- nil in the default language itself.
      def original(field)
        return nil if locale == ::Locales.default

        asset.public_send(field, locale: ::Locales.default)
      end

      # The switcher's markers (translation helpers spec §4): missing where
      # the original has alt text and this language doesn't (the image
      # rule in `Translations::Status`), outdated where alt or caption was
      # translated from an older original.
      def missing_locales = switcher_locales[:missing]

      def outdated_locales = switcher_locales[:outdated]

      # See `Admin::RecordHeaderComponent#switcher_locales`.
      def switcher_locales = @switcher_locales ||= Translations::Status.switcher_locales(asset)

      # See `Admin::PageSettingsFormComponent#translation`.
      def translation(field) = Admin::TranslationScreen::OutdatedNoteComponent.options_for(asset, field, locale: locale, confirmable: editable?)

      def language_url
        ->(code) { helpers.admin_medium_path(asset, **(code.to_s == ::Locales.default ? {} : { locale: code })) }
      end

      def index_path = helpers.admin_media_path(**url_options)

      def destroy_path = helpers.admin_medium_path(asset, **url_options)

      def delete_dialog_id = "delete-media-#{asset.id}"

      # Whether Delete is even offered at all -- an asset's own uploader
      # or a `media.manage` holder, same gate as every field above.
      def can_delete? = editable?

      def used? = defined?(@used) ? @used : (@used = asset.used?)

      # `:unused` / `:in_use` / `:trash_only` (trash spec §4.1/§5.1) --
      # memoized for the same reason `#usage_entries` is: the template reads
      # it more than once (the "Used on" empty-state branch, Task 10's
      # Move-to-trash gate).
      def usage_state = defined?(@usage_state) ? @usage_state : (@usage_state = asset.usage_state)

      # Move to trash is refused only while a *kept* page or post still uses
      # the image (`Trash::Move`'s own check, `Media::Asset
      # #used_by_kept_owner?`) -- not merely `used?`, which also counts a
      # usage by something already in the trash (`usage_state == :trash_only`)
      # or one whose owner can't even be resolved any more (a stale index
      # row). Both of those are cases `Trash::Move` would actually let
      # through, so disabling the button for them would refuse something the
      # server wouldn't.
      def move_to_trash_disabled? = usage_state == :in_use

      # The same wording `Trash::Move`'s own refusal uses
      # (`Media::Asset#in_use_message(kept_only: true)`), so the disabled
      # button's reason and the 422 an editor would get from forging past it
      # never disagree. Memoized like `#usage_state`/`#usage_entries` above:
      # the template reads it twice (the disabled button's own `title:` and
      # the paragraph under it), and `#in_use_message` runs its own queries.
      def in_use_reason = defined?(@in_use_reason) ? @in_use_reason : (@in_use_reason = asset.in_use_message(kept_only: true))

      # "Used on" (design spec §6): one entry per distinct place, grouped
      # the same way `Media::Asset#usages_summary` already groups its raw
      # `media_usages` rows -- a block's own usage is named by the page or
      # post it sits on (`Media::Asset#usage_place_of`'s own reasoning: nobody
      # editing this asset cares that a "block_image" row's `owner_type` is
      # technically `ContentBlock`, they care which page shows it). Only
      # an owner the current viewer can actually read
      # (`pages.read`/`posts.read`) becomes a link; unreadable becomes a
      # neutral label (global constraints' own "Used on" ruling) --
      # exactly `Admin::AuditEventsHelper#audit_subject_path`'s rule,
      # reapplied here since neither that helper nor `Media::Asset`'s own
      # (text-only) `#in_use_message` is built to hand back a
      # clickable link.
      #
      # Memoized (final fix wave, M7): the template reads it twice (the
      # empty check and the list), and each call ran `#usages_summary`'s
      # queries again.
      #
      # Kept places only (trash spec §5.1) -- a trashed page or post (or a
      # block sitting on one, the same second hop `Media::Usage
      # .by_kept_owner`/`Media::Asset#used_by_kept_owner?` use) is skipped
      # here, not merely unlinked: naming it would disclose a record this
      # screen has no business surfacing outside the Trash. `#usage_state`
      # is what tells an editor "used only by items in the trash" instead;
      # `#unresolved_usage?` still covers a *genuinely* stale row (no owner
      # at all), which `place_for` also reads as `nil` and this list also
      # drops.
      def usage_entries
        @usage_entries ||= usage_summary.filter_map do |entry|
          place = place_for(entry[:owner])
          next if place.nil? || place.trashed?

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

      # Used, but by nothing this panel can name (final fix wave, M7): a
      # `media_usages` row whose owner is gone entirely, or a block with no
      # page/post of its own -- `place_for` reads `nil` in both cases. Kept
      # deliberately separate from `#usage_state`'s `:trash_only` (Task 4):
      # a *trashed* owner still resolves fine (`place_for` returns it,
      # `#usage_entries` just chooses not to list it), so it takes the more
      # specific "used only by items in the trash" message instead of this
      # generic "may be out of date" one -- checked first in the template,
      # since a single asset could in principle carry both kinds of row.
      def unresolved_usage? = used? && usage_summary.any? { |entry| place_for(entry[:owner]).nil? }

      private

      attr_reader :asset, :locale, :url_options, :notice, :alert

      # The raw, ungrouped-by-visibility `usages_summary` rows, memoized
      # once: `#usage_entries` and `#unresolved_usage?` both need to walk
      # them (the former to build the visible list, the latter to check for
      # a row `place_for` can't resolve at all), and neither should re-run
      # `usages_summary`'s own queries to do it.
      def usage_summary
        @usage_summary ||= asset.usages_summary
      end

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
