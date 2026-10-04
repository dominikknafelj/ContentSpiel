module Admin
  module EditorScreen
    # The New page dialog (`new-page-dialog`, 560 wide), rendered ONCE in the
    # layout outside `#content` (forms can't nest; the tree, the pages empty
    # state, ⌘K and the dashboard all open this one). Opened with
    #
    #   data: dialog_trigger("new-page-dialog").merge(
    #     "new-page-parent-id-param": id, "new-page-title-param": text)
    #
    # `admin--dialog#open` announces the opening (`admin--dialog:opening`) and
    # `admin--new-record` presets Inside and Title from the trigger's
    # `data-new-page-*-param` attributes. Nothing is rendered for a viewer who
    # may not create a page anywhere (`NewPageFormComponent#creatable?`); a
    # trigger then simply falls through to its `href`, the no-JS page.
    class NewPageDialogComponent < Admin::AdminComponent
      ID = "new-page-dialog".freeze

      def initialize(url_options: {}, locale: ::Locales.default)
        @form = NewPageFormComponent.new(url_options: url_options, locale: locale)
      end

      def render? = form.render?

      private

      attr_reader :form
    end
  end
end
