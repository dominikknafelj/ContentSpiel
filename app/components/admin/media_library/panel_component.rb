module Admin
  # See `Admin::MediaLibrary::GridComponent`'s own class comment for why
  # this namespace is `MediaLibrary`, not `Media`.
  module MediaLibrary
    # One image's side panel (round 3, Task 8, handoff §4.6 and B19; it replaced
    # the detail page, `Admin::MediaController#show`, which now redirects to
    # `/media?selected=ID`): the preview, the file's facts in mono, the
    # language tabs, an autosaving title/alt/caption form (`Media::Save`,
    # alt/caption per locale), "Used on" and Move to trash with its help text.
    # The form is the detail page's own, moved: it saves through the write
    # queue (`admin--saving--autosave`) and its answer (`Admin::MediaController#update`)
    # also moves the tile and the segment counts, so nothing reloads under the
    # typing editor. The panel is narrower than 880px, so the translation pair
    # stacks on its own (`container-type` on the form).
    #
    # Slots (`Admin::Slots`): `media.panel.header` stands at the right end of
    # the file-name row, above the preview, and `media.panel.sections` below
    # "Used on", OUTSIDE the autosave form: what a feature draws there brings
    # forms of its own, and a form cannot nest. Features register what stands
    # there in `config/initializers/admin_slots.rb`; each is built with the
    # image, the viewer and the panel's `locale:` and `url_options:`.
    #
    # `link_params` is the grid's own state (`q`, `filter`, `page`, symbol keys,
    # never `locale`, which `url_options` carries): every link out of the panel
    # (the language tabs, the close button) and the form's own URL keep it, so
    # the screen behind the panel is the one the editor left.
    #
    # `editable?` mirrors `Media::Ownership` (the service this form's own
    # `update` endpoint actually enforces): `media.manage`, or being this
    # asset's own uploader. Unlike a page/post, an asset has no `can_edit?`
    # of its own in `AccessControlHelper` (that method's own case statement
    # only knows `Post`/`Page`) -- ownership isn't a permission `can?` can
    # answer on its own, so this asks it directly rather than trying to
    # force a `Post`/`Page`-shaped question onto a record that isn't
    # either. A viewer this says no to sees the same facts as plain text (no
    # inputs, no Move to trash; handoff B19) and the sentence naming who may
    # edit -- the whole module only ever needs `media.upload` to be read.
    class PanelComponent < Admin::AdminComponent
      ROLE_LABELS = { "hero" => "Hero image", "block_image" => "Image block", "rich_text" => "Rich text" }.freeze

      def initialize(asset:, locale:, url_options: {}, link_params: {})
        @asset = asset
        @locale = locale.to_s
        @url_options = url_options
        @link_params = link_params.to_h.symbolize_keys
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

      # "image/png · 68 B · 1 × 1px", the file's own facts on one mono line.
      def file_facts = [ asset.content_type, byte_size, dimensions ].compact.join(" · ")

      def filename = asset.file.attached? ? asset.file.filename.to_s : nil

      # "2 Oct 2026", in the site time zone (`Admin::BaseController` runs every
      # request inside it).
      def uploaded_on = asset.created_at.in_time_zone.strftime("%-d %b %Y")

      def uploader? = asset.created_by_id.present?

      def uploader = asset.created_by

      # Who is looking, for the slots: the actor `can?` already asks about.
      # What `#media-panel-title` holds: the name, and the name again as its
      # `title`, because the row cuts a long one short. One place for it: the
      # panel draws it and `Admin::MediaController`'s autosave answer updates
      # the heading with it (`view`: whatever has the tag helpers).
      def self.title_content(asset, view) = view.tag.span(asset.title, title: asset.title)

      def viewer = Current.actor

      # What every slot of the panel is handed beside the image and the viewer.
      def slot_context = { locale: locale, url_options: url_options }

      def status_id = "media-save-status"

      def base_updated_at_id = "media-base-updated-at"

      def base_updated_at_value = asset.updated_at.iso8601(6)

      # The form's own URL carries the grid's state so the answer can move the
      # tile (its link keeps the same state) and recount the segments for the
      # same search.
      def form_url = helpers.admin_medium_path(asset, **link_params, **url_options)

      def form_data
        return {} unless editable?

        {
          controller: "admin--saving--autosave",
          action: "input->admin--saving--autosave#queue change->admin--saving--autosave#queue focusout->admin--saving--autosave#saveNow",
          "admin--saving--autosave-status-id-value": status_id
        }
      end

      def title_value = asset.title

      def title_errors = asset.errors.full_messages_for(:title)

      # Mobility's own per-locale accessor (`locale:`), not the plain
      # reader -- this is the asset's own literal default in the locale
      # being edited, the same "no cross-locale fallback while editing"
      # rule every other translated column's own admin field already
      # follows (`Admin::EditorScreen::BlockCardComponent#value_for`'s own comment).
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

      # See `Admin::EditorScreen::HeaderComponent#switcher_locales`.
      def switcher_locales = @switcher_locales ||= Translations::Status.switcher_locales(asset)

      # See `Admin::EditorScreen::PageSettingsFormComponent#translation`.
      def translation(field) = Admin::EditorScreen::ReferenceCardComponent.options_for(asset, field, locale: locale, confirmable: editable?)

      # The tabs keep `selected` and the grid's state; only the language changes.
      def language_url
        ->(code) { helpers.admin_media_path(**link_params, selected: asset.id, **(code.to_s == ::Locales.default ? {} : { locale: code })) }
      end

      # × : the grid alone, as the editor left it.
      def close_path = helpers.admin_media_path(**link_params, **url_options)

      def destroy_path = helpers.admin_medium_path(asset, **link_params, **url_options)

      # The Alt field's warn border (handoff §4.6, "warn border when empty"):
      # asked of the DEFAULT language's alt, whatever tab is open, since that is
      # the text every other language falls back to. Only the class is decided
      # here; the border itself is drawn while the input is empty
      # (`:placeholder-shown`, `.admin-media-alt-warn` in the stylesheet), so it
      # goes as soon as the editor types and needs no stream.
      def alt_warn? = asset.alt(locale: ::Locales.default).to_s.strip.empty?

      ALT_PLACEHOLDER = "Add alt text".freeze

      # "Kept in Trash for 30 days." / "Kept in Trash until someone empties it."
      # (`site_settings.trash_retention_days`, 0 = never purged automatically).
      def retention_help
        days = Current.site.trash_retention_days.to_i
        days.positive? ? "Kept in Trash for #{helpers.pluralize(days, "day")}." : "Kept in Trash until someone empties it."
      end

      # "Only by items in the trash: “About”, “Pricing”." naming only the owners
      # this viewer may read (a trashed page or post they couldn't open is not
      # named, the same rule as the kept list's "a page you can't open"); the
      # bare sentence when there is none to name.
      def trash_only_message
        names = trash_only_names
        names.any? ? "Only by items in the trash: #{names.to_sentence}." : "Only by items in the trash."
      end

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

      # Why the disabled button is disabled, as whole sentences (design pass
      # bug 7): the count of kept places that use the image, read from the
      # same `#usage_entries` the "Used on" list below shows, so the two
      # never disagree. (`Trash::Move`'s own refusal wording stays
      # `Media::Asset#in_use_message`; this is the editor-facing explanation.)
      # One whole string per case -- never assembled from sentence parts.
      # Zero entries while still `:in_use` means every kept usage is one this
      # panel can't name (an unresolvable row), which `Trash::Move` still
      # refuses.
      def in_use_reason
        @in_use_reason ||=
          case usage_entries.size
          when 0 then "In use somewhere that can’t be shown. Remove it there first."
          when 1 then "In use on 1 #{usage_entries.first[:kind]}. Remove it there first."
          else "In use in #{usage_entries.size} places. Remove it there first."
          end
      end

      # "Used on" (design spec §6): one entry per distinct place, grouped
      # the same way `Media::Asset#usages_summary` already groups its raw
      # `media_usages` rows -- a block's own usage is named by the page or
      # post it sits on (`Media::Asset#usage_place_of`'s own reasoning: nobody
      # editing this asset cares that a "block_image" row's `owner_type` is
      # technically `ContentBlock`, they care which page shows it). Only
      # an owner the current viewer can actually read
      # (`pages.read`/`posts.read`) becomes a link; unreadable becomes a
      # neutral label (global constraints' own "Used on" ruling) --
      # exactly the audit log's rule (`Audit::Sentence::Targets`),
      # reapplied here since neither that nor `Media::Asset`'s own
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
            { label: "#{role_label} — #{kind} “#{Audit::Snapshot.label_for(place)}”#{locale_suffix}", path: place_path(place, kind), kind: kind }
          else
            { label: "#{role_label} — a #{kind} you can't open#{locale_suffix}", path: nil, kind: kind }
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

      attr_reader :asset, :locale, :url_options, :link_params

      def trash_only_names
        usage_summary.filter_map do |entry|
          place = place_for(entry[:owner])
          next unless place&.trashed?

          kind = place.is_a?(Post) ? "post" : "page"
          "“#{Audit::Snapshot.label_for(place)}”" if can?("#{kind}s.read", place)
        end.uniq
      end

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
