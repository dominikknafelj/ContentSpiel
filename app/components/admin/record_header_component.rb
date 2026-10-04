module Admin
  # The page editor's own header (cs-studio spec §5.1): title, the public
  # URL (copy + open), the status badge, Publish now/Unpublish/Schedule…,
  # Delete, the "Live" note, and the autosave status line. Every action
  # here is its own plain form/link, not routed through the settings
  # form's autosave -- publishing and deleting are deliberate, one-shot
  # actions (spec §5.1's own "Publish now / Unpublish / Schedule…, Delete"
  # list), unlike a field that saves itself the moment an editor stops
  # typing.
  #
  # The flash a publish/unpublish/schedule redirect leaves is the layout's
  # toasts (`Admin::ToastRegionComponent`), not this header's.
  class RecordHeaderComponent < AdminComponent
    def initialize(page:, locale:, url_options: {})
      @page = page
      @locale = locale
      @url_options = url_options
    end

    def status = page.status

    def live? = page.live?

    # Only meaningful for a scheduled page (`StatusChipComponent` itself
    # ignores `at:` for every other status), but harmless to pass either
    # way -- simpler than branching here on the exact same condition that
    # component already re-checks internally.
    def scheduled_at = page.published_at

    def save_status_id = "page-save-status"

    # The page's own address, always shown (even a draft has a would-be
    # URL, from its cached path) so there's something to copy ahead of
    # publishing -- `View on site`'s own link is gated on `live?` below
    # instead, since opening a draft's public address is a dead end
    # (spec §6.4 makes the same call for the preview banner's "View live").
    def public_path = urls.path_for(page, locale)

    def public_url = urls.url_for(page, locale)

    def preview_path = preview_urls.path_for(page, locale)

    # Access control (design spec §5 "Everywhere"): Publish now, Unpublish
    # and Schedule… need `pages.publish` on this page, Delete `pages.delete`
    # -- each absent, not disabled, without it (the disabled Delete below is
    # only for a user who *may* delete, but not this page right now). A page
    # the user can read but not edit (`can_edit?`) says "View only".
    def editable? = defined?(@editable) ? @editable : (@editable = can_edit?(page))

    def may_publish? = can?("pages.publish", page)

    def may_delete? = can?("pages.delete", page)

    def can_publish? = !page.live? && may_publish?

    def can_unpublish? = page.status != "draft" && may_publish?

    # Trash spec §4.1: moving a page to the trash takes its whole branch
    # with it (`Trash::Move`), so a page with subpages is no longer refused
    # the way permanent deletion was -- only the homepage still is
    # (`Page#only_one_root_page`, and `Trash::Move`'s own "The homepage
    # can't be moved to the trash" refusal).
    def can_delete? = !page.root?

    def delete_disabled_reason
      "The homepage can't be deleted" if page.root?
    end

    # How many kept descendants would come along (Task 10): read once,
    # since both `#delete_dialog_body` and its own template read it, and
    # each read is a `closure_tree` query.
    def kept_descendant_count = defined?(@kept_descendant_count) ? @kept_descendant_count : (@kept_descendant_count = page.descendants.kept.count)

    # "You can restore it from the trash." -- the dialog's own reassurance
    # that this isn't `Trash::Purge` -- plus, only when subpages are coming
    # along too, a second sentence naming how many (trash spec Review Focus
    # 1's "a branch moves together" made visible here, not just enforced by
    # the service).
    def delete_dialog_body
      body = "You can restore it from the trash."
      body += " This also moves #{helpers.pluralize(kept_descendant_count, "subpage")} to the trash." if kept_descendant_count.positive?
      body
    end

    def delete_dialog_id = "delete-page-#{page.id}"

    def scheduled_at_input_value
      (page.status == "scheduled" ? page.published_at : Time.current + 1.day).strftime("%Y-%m-%dT%H:%M")
    end

    # The dot-marked codes for `Admin::LanguageTabsComponent` (spec
    # §6.2) -- computed here, not handed in, since every caller of this
    # component already has the one `page` it's for and nothing else this
    # check would need.
    def missing_locales = switcher_locales[:missing]

    # The switcher's "original changed" codes (translation helpers spec §4)
    # -- the page's own fields and its blocks', which roll up into it.
    def outdated_locales = switcher_locales[:outdated]

    # Both marker sets from one `Translations::Status` pass (one blocks
    # query), read once per render.
    def switcher_locales = @switcher_locales ||= Translations::Status.switcher_locales(page)

    # Per-code URL for the switcher: this same page's editor, with `locale:`
    # omitted for the site's default language -- the same "the default
    # language's own URL never carries a `?locale=`" rule `Admin::
    # BaseController#admin_url_options` already applies to the *current*
    # locale, just rebuilt here once per candidate code rather than the one
    # this component was itself rendered with.
    def language_url
      ->(code) { helpers.admin_page_path(page, **(code.to_s == ::Locales.default ? {} : { locale: code })) }
    end

    private

    attr_reader :page, :locale, :url_options

    # Absolute addresses (the "Copy" button) use the configured public
    # origin, or -- with none configured, as on a local checkout -- the
    # origin this very request came in on, which is where the site is
    # actually being served.
    def urls = PublicSite::Urls.new(host: PublicSite::Urls.configured_host || helpers.request.base_url)

    def preview_urls = PublicSite::Urls.new(preview: true)
  end
end
