module Admin
  module EditorScreen
    # The New post dialog (`new-post-dialog`, 560 wide), once in the layout like
    # `NewPageDialogComponent`. Opened with `dialog_trigger("new-post-dialog")`
    # merged with `"new-post-type-param"` (preselect a type, e.g. from the Posts
    # list's split button) and `"new-post-title-param"`; `admin--new-record`
    # presets them. Rendered only for a viewer who may create at least one type.
    class NewPostDialogComponent < Admin::AdminComponent
      ID = "new-post-dialog".freeze

      def initialize(url_options: {}, locale: ::Locales.default)
        @form = NewPostFormComponent.new(url_options: url_options, locale: locale)
      end

      def render? = form.render?

      private

      attr_reader :form
    end
  end
end
