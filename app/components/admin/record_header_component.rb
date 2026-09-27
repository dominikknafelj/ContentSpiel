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
  # `notice:`/`alert:` are the flash a publish/unpublish/schedule redirect
  # (or a failed delete's own re-render) leaves for this header to show
  # (`Admin::PagesController`) -- read by the view, not by this component,
  # since a component has no controller context of its own to pull
  # `flash` from.
  class RecordHeaderComponent < AdminComponent
    def initialize(page:, locale:, url_options: {}, notice: nil, alert: nil)
      @page = page
      @locale = locale
      @url_options = url_options
      @notice = notice
      @alert = alert
    end

    def status = page.status

    def live? = page.live?

    # Only meaningful for a scheduled page (`StatusBadgeComponent` itself
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

    def can_publish? = !page.live?

    def can_unpublish? = page.status != "draft"

    def can_delete? = !page.root? && page.children.empty?

    def delete_disabled_reason
      return "The homepage can't be deleted" if page.root?
      return "Delete its subpages first" unless page.children.empty?

      nil
    end

    def delete_dialog_id = "delete-page-#{page.id}"

    def scheduled_at_input_value
      (page.status == "scheduled" ? page.published_at : Time.current + 1.day).strftime("%Y-%m-%dT%H:%M")
    end

    private

    attr_reader :page, :locale, :url_options, :notice, :alert

    def urls = PublicSite::Urls.new

    def preview_urls = PublicSite::Urls.new(preview: true)
  end
end
