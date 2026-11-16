module Admin
  module HistoryScreen
    # The History screen's heading row (the StudioHistory card, "Route and
    # crumbs", "Head row"): the editor's crumbs with the record's title
    # linking back to it and "History" last, then the title as the `h1`, its
    # state as the editor's header draws it (the status chip, Live shown, and
    # the unpublished chip) and "Back to editor", the head's only action. A
    # crumb the viewer may not open is plain text, as in the editor's header.
    class HeadComponent < Admin::AdminComponent
      def initialize(record:, locale:, url_options: {})
        @record = record
        @locale = locale.to_s
        @url_options = url_options
      end

      attr_reader :record, :locale, :url_options

      def page? = record.is_a?(::Page)

      def title = ::Locales.read(record, :title, locale: locale)

      def state = @state ||= ::Publishing::State.of(record)

      def editor_url = helpers.public_send(page? ? :admin_page_path : :admin_post_path, record, **url_options)

      # [label, url-or-nil] per crumb before the record's own.
      def crumbs
        if page?
          pages = [ t(".pages"), can?("pages.read") && !record.root? ? helpers.admin_pages_path(**url_options) : nil ]
          [ pages ] + record.ancestors.to_a.reverse.map do |ancestor|
            [ ::Locales.read(ancestor, :title, locale: locale), can?("pages.read", ancestor) ? helpers.admin_page_path(ancestor, **url_options) : nil ]
          end
        else
          allowed = can?("posts.read")
          label = ::ContentTypes.find(record.content_type)&.label || record.content_type
          [ [ t(".posts"), allowed ? helpers.admin_posts_path(**url_options) : nil ],
            [ label, allowed ? helpers.admin_posts_path(type: record.content_type, **url_options) : nil ] ]
        end
      end
    end
  end
end
