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

      # [label, url-or-nil] per crumb before the record's own
      # (`Admin::RecordCrumbsHelper`, the editor header's), the module's
      # crumb worded here.
      def crumbs
        helpers.record_crumbs(record, locale: locale, url_options: url_options, can: ->(key, subject) { can?(key, subject) })
          .map { |label, url| [ label.is_a?(Symbol) ? t(".#{label}") : label, url ] }
      end
    end
  end
end
