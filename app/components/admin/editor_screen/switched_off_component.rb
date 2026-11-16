module Admin
  module EditorScreen
    # Above a dormant post's form, in the place of the view-only hint and
    # replacing it for this cause (the hint's reason, "needs the right to
    # publish", would be the wrong one): a neutral note saying the post's type
    # is switched off, that its posts are kept and not on the site, and how
    # to change it. A holder of `settings.manage` is linked to Settings' Post
    # types card; anyone else is told who can switch it on. Navigation only:
    # `can?` here gates a link, never a write (the services refuse those).
    class SwitchedOffComponent < Admin::AdminComponent
      def initialize(record:, url_options: {})
        @record = record
        @url_options = url_options
      end

      def render? = !record.type_switched_on?

      def type = ::ContentTypes.find(record.content_type)&.label || record.content_type

      def settings? = can?("settings.manage")

      def settings_path = helpers.admin_settings_path(anchor: "post_types", **url_options)

      private

      attr_reader :record, :url_options
    end
  end
end
