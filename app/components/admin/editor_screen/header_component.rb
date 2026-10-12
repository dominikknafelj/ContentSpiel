module Admin
  module EditorScreen
    # The one sticky header of the page and the post editor (design pass
    # round 2, handoff §4.1 and §9 B15): a breadcrumb row carrying the save
    # status, Preview, ONE primary action and a ⋯ menu; the title with its
    # status chip; the public path; the language tabs. One component serves
    # both editors so their publish forms can't drift apart (a publish must
    # carry `turbo_frame: "_top"` to refresh the sidebar's badge and the
    # lists).
    #
    # "No drafts" variant (spec §2): an edit to a live record goes live at
    # once, so a live record has no primary button at all -- only the hint
    # that says so -- while a draft offers Publish and a scheduled record
    # Publish now plus Edit schedule. Everything else (Activity, Schedule…,
    # Unpublish, Move to trash) sits in the ⋯ menu, the destructive item last
    # and after a divider.
    #
    # Every publish/unpublish/schedule/delete form carries `data-turbo-frame=
    # "_top"`: each redirects, and left to the layout's `<turbo-frame
    # id="content">` its answer would replace only that frame, leaving the
    # tree column and the sidebar's Trash badge showing what they showed
    # before. A full-page visit re-renders them for free.
    #
    # The dialogs (schedule, unpublish, delete) are siblings AFTER the `<header>`, not
    # inside it: the header is sticky with its own stacking context, and a
    # modal opened from within it would be clipped by it. Dialog forms still
    # cannot nest in the editor form -- the header is never inside one.
    #
    # Slots (`Admin::Slots`): the action row draws what features register at
    # `editor.header.people` (first, before the saved status) and
    # `editor.header.actions` (after it, before Preview) -- features register
    # what stands there in `config/initializers/admin_slots.rb`. Each is built
    # with the record, the viewer and `slot_context`: what the screen has
    # already read that a feature would read again, handed through untouched.
    #
    # Slot: `suggest` is the right-aligned end of the language row (today
    # `TranslateAllComponent`, rendered by the caller). Under the rows the
    # header itself owns two things: the view-only hint, and the empty
    # `#editor-notice` a stale autosave's 409 fills with the "Changed
    # elsewhere" bar.
    class HeaderComponent < Admin::AdminComponent
      renders_one :suggest

      def initialize(record:, locale:, url_options: {}, slot_context: {}, hold_strip: nil)
        raise ArgumentError, "the editor header is for a Page or a Post, not #{record.class}" unless record.is_a?(::Page) || record.is_a?(::Post)

        @record = record
        @locale = locale.to_s
        @url_options = url_options
        @slot_context = slot_context
        @hold_strip = hold_strip
      end

      # Who is looking, for the slots: the actor `can?` already asks about.
      def viewer = Current.actor

      # What every slot of the header is handed beside the record and the viewer.
      def slot_context = { locale: locale, url_options: url_options, **@slot_context }

      def page? = record.is_a?(::Page)

      # "page" / "post": the noun in copy, ids and route names.
      def type = page? ? "page" : "post"

      def title = ::Locales.read(record, :title, locale: locale)

      def status = record.status

      def live? = record.live?

      def scheduled? = status == "scheduled"

      def scheduled_at = record.published_at

      def save_status_id = "#{type}-save-status"

      def delete_dialog_id = "delete-#{type}-#{record.id}"

      def unpublish_dialog_id = "unpublish-#{type}-#{record.id}"

      # The menu's "Schedule…" and a scheduled record's "Edit schedule" open
      # the `ScheduleDialogComponent`, rendered after the header.
      def schedule_dialog_id = ScheduleDialogComponent.dialog_id_for(record)

      # What the last refused `schedule` post left in the flash (the
      # controller's own wording); read once, here, so the dialog reopens with
      # it. Never `flash[:alert]`: that is the toast region's, and a form
      # error is not a toast.
      def schedule_error = helpers.flash[:schedule_error]

      # What the editor typed, carried back with it.
      def schedule_value = helpers.flash[:schedule_value]

      # The record's own address, always shown while it has one (a draft page
      # has a would-be URL, so there is something to copy ahead of publishing;
      # "View on site" is gated on `live?` instead -- a draft's public address
      # is a dead end). A post nobody lists has none.
      def public_path = urls.path_for(record, locale)

      def public_url = absolute_urls.url_for(record, locale)

      def preview_path = preview_urls.path_for(record, locale)

      # Access control (design spec §5 "Everywhere"): publishing, unpublishing
      # and scheduling need `<pages|posts>.publish` on the record, moving it to
      # the trash `.delete` -- absent, not disabled, without them. A readable
      # record the viewer cannot edit says "View only".
      def editable? = defined?(@editable) ? @editable : (@editable = can_edit?(record))

      # Why a record that is readable cannot be changed -- one whole string per
      # case. The editing right is there but the record is published (or
      # scheduled) and the viewer cannot publish: `can_edit?`'s own rule
      # ("editing a published record needs publish too", the interim rule
      # until revisions exist).
      def view_only_hint
        hint = "You can view this #{type} but not change it."
        return hint unless can?("#{type}s.edit", record) && record.published_at.present?

        "#{hint} It is #{live? ? "live" : "scheduled"}, and changing a #{live? ? "live" : "scheduled"} #{type} needs the right to publish."
      end

      def may_publish? = can?("#{type}s.publish", record)

      def may_delete? = can?("#{type}s.delete", record)

      def can_publish? = !live? && may_publish?

      # Whoever may publish this record may publish what is in it (D5). Shown
      # for every published or scheduled record until Task 6 knows whether
      # there is anything to publish.
      def can_publish_changes? = record.published_at.present? && may_publish?
      def publish_changes_url = helpers.admin_publishing_publish_path(kind: type, id: record.id, **url_options)

      def can_unpublish? = status != "draft" && may_publish?

      # Only a draft is scheduled from the menu; a scheduled record edits its
      # schedule from the header's own button, a live one is not scheduled.
      def can_schedule? = status == "draft" && may_publish?

      def can_edit_schedule? = scheduled? && may_publish?

      def primary_label = scheduled? ? "Publish now" : "Publish"

      # Trash spec §4.1: a page with subpages moves its whole branch, so only
      # the homepage is refused (`Page#only_one_root_page`, `Trash::Move`).
      def can_delete? = !(page? && record.root?)

      def delete_disabled_reason
        "The homepage can’t be deleted" if page? && record.root?
      end

      def kept_descendant_count
        return 0 unless page?

        defined?(@kept_descendant_count) ? @kept_descendant_count : (@kept_descendant_count = record.descendants.kept.count)
      end

      def delete_dialog_body
        body = "You can restore it from the trash."
        body += " This also moves #{helpers.pluralize(kept_descendant_count, "subpage")} to the trash." if kept_descendant_count.positive?
        body
      end

      # Handoff §10 A8: unpublishing is reversible, so its dialog is a plain
      # confirmation; it only says what the site will show.
      def unpublish_dialog_body
        body = "It will show “not found” on the site."
        body += " Subpages also show not found." if kept_descendant_count.positive?
        body
      end

      def live_hint = "This #{type} is live. Changes appear on the site as soon as they’re saved."

      # Whether the ⋯ menu has anything to hold (a viewer who can only read
      # gets no empty menu).
      def menu_items?
        can?("audit.view") || can_schedule? || can_unpublish? || may_delete?
      end

      # [label, url-or-nil] per crumb; a crumb the viewer may not open is plain
      # text. A page: "Pages" and each ancestor, root first. A post: "Posts" and
      # its content type's filtered list.
      def breadcrumb
        if page?
          # On Home itself "Pages" would link to the page you are on (`/pages`
          # opens Home), so it is plain text there.
          pages_crumb = [ "Pages", can?("pages.read") && !record.root? ? helpers.admin_pages_path(**url_options) : nil ]
          ancestors = record.ancestors.to_a.reverse.map do |ancestor|
            [ ::Locales.read(ancestor, :title, locale: locale), can?("pages.read", ancestor) ? helpers.admin_page_path(ancestor, **url_options) : nil ]
          end
          [ pages_crumb ] + ancestors
        else
          allowed = can?("posts.read")
          label = ::ContentTypes.find(record.content_type)&.label || record.content_type
          [ [ "Posts", allowed ? helpers.admin_posts_path(**url_options) : nil ],
            [ label, allowed ? helpers.admin_posts_path(type: record.content_type, **url_options) : nil ] ]
        end
      end

      def publish_url = route("publish")

      def unpublish_url = route("unpublish")

      def record_url = helpers.public_send("admin_#{type}_path", record, **url_options)

      def activity_url = helpers.admin_audit_events_path(subject_type: record.class.name, subject_id: record.id, **url_options)

      # The missing / outdated language marks, from one `Translations::Status`
      # pass (one blocks query), read once per render.
      def missing_locales = switcher_locales[:missing]

      def outdated_locales = switcher_locales[:outdated]

      def switcher_locales = @switcher_locales ||= Translations::Status.switcher_locales(record)

      # Per-code URL for the language tabs: this record's editor, `locale:`
      # omitted for the site's default language (the same rule
      # `Admin::BaseController#admin_url_options` applies to the current one).
      def language_url
        ->(code) { helpers.public_send("admin_#{type}_path", record, **(code.to_s == ::Locales.default ? {} : { locale: code })) }
      end

      private

      attr_reader :record, :locale, :url_options

      def route(action) = helpers.public_send("#{action}_admin_#{type}_path", record, **url_options)

      def urls = PublicSite::Urls.new

      # The "Copy" address uses the configured public origin, or -- with none,
      # as on a local checkout -- the origin this request came in on. Its own
      # instance: reading the request needs the view context, which the path
      # readers above must not.
      def absolute_urls = PublicSite::Urls.new(host: PublicSite::Urls.configured_host || helpers.request.base_url)

      def preview_urls = PublicSite::Urls.new(preview: true)
    end
  end
end
