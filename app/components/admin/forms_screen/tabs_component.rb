module Admin
  module FormsScreen
    # A form's two screens, Form | Submissions, drawn
    # as the Trash screen's tabs are (`Admin::Ui::SegmentedComponent`'s links):
    # plain links, the current one chosen and `aria-current`. Each tab is drawn only for a viewer who may open it
    # (the builder `forms.manage`, the submissions `form_submissions.view`),
    # and a viewer who may open only one gets no tabs at all: a single tab
    # says nothing.
    class TabsComponent < Admin::AdminComponent
      # `current` is :form or :submissions.
      def initialize(form:, current:, url_options: {})
        @form = form
        @current = current
        @url_options = url_options
      end

      def render? = tabs.size > 1

      def tabs
        @tabs ||= [
          ({ label: t(".form"), href: helpers.admin_form_path(@form, **@url_options), current: @current == :form } if can?("forms.manage")),
          ({ label: t(".submissions"), href: helpers.admin_form_submissions_path(@form, **@url_options), current: @current == :submissions } if can?("form_submissions.view"))
        ].compact
      end

      def call
        render Admin::Ui::SegmentedComponent.new(mode: :links, segments: tabs, label: t(".label"), control_data: { turbo_frame: "content" })
      end
    end
  end
end
