module Admin
  module EditorScreen
    # "Change this page's address": a published or scheduled page's slug, in
    # the language being edited, with what it does said before it is done
    # (drafts spec D7). A slug is in no published copy: a new one moves the
    # page's address at once, so it is not a field of the autosaving settings
    # form but this form, behind a confirmation, which goes through the write
    # queue's hold like the other instant actions (`admin--saving--queue-hold`)
    # and is refused by `Admin::PagesController#slug` while another tab holds
    # the settings.
    #
    # The dialog is drawn by the page's show view, beside the live region and
    # never inside the settings form: a form in a form is invalid, and a
    # second form inside an autosaving one would be read by the write queue
    # as part of it. A draft has no dialog (`render?`): its slug is a field of
    # the settings form. The homepage has no slug at all.
    class SlugDialogComponent < Admin::AdminComponent
      def self.dialog_id_for(page) = "page-slug-#{page.id}"

      def initialize(page:, locale:, url_options: {})
        @page = page
        @locale = locale.to_s
        @url_options = url_options
      end

      def render? = page.parent_id.present? && page.published_at.present?

      def dialog_id = self.class.dialog_id_for(page)

      def form_id = "#{dialog_id}-form"

      def input_id = "#{dialog_id}-slug"

      def url = helpers.slug_admin_page_path(page, **url_options)

      def value = Mobility.with_locale(locale) { page.slug }

      private

      attr_reader :page, :locale, :url_options
    end
  end
end
