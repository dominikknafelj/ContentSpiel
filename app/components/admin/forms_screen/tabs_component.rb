module Admin
  module FormsScreen
    # A form's two screens, Form | Submissions (design.md 2.1 and 3), drawn
    # as the Trash screen's tabs (`Admin::TrashScreen::TabsComponent`'s
    # segmented look): plain links, the current one inverted and
    # `aria-current`. Each tab is drawn only for a viewer who may open it
    # (the builder `forms.manage`, the submissions `form_submissions.view`),
    # and a viewer who may open only one gets no tabs at all: a single tab
    # says nothing.
    class TabsComponent < Admin::AdminComponent
      LINK_CLASS = Admin::TrashScreen::TabsComponent::LINK_CLASS

      # `current` is :form or :submissions.
      def initialize(form:, current:, url_options: {})
        @form = form
        @current = current
        @url_options = url_options
      end

      def render? = tabs.size > 1

      def tabs
        @tabs ||= [
          ({ key: :form, label: t(".form"), href: helpers.admin_form_path(@form, **@url_options) } if can?("forms.manage")),
          ({ key: :submissions, label: t(".submissions"), href: helpers.admin_form_submissions_path(@form, **@url_options) } if can?("form_submissions.view"))
        ].compact
      end

      def link_class(key)
        "#{LINK_CLASS} #{key == @current ? "bg-ink font-semibold text-paper" : "text-meta hover:bg-sunken"}"
      end
    end
  end
end
