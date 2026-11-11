module Admin
  module Ui
    # `Admin::Ui::BadgeComponent`: neutral, warn, accent (the MCP channel's),
    # and a badge with a mark before its label (a scope chip's type dot).
    class BadgeComponentPreview < ViewComponent::Preview
      def neutral = render(Admin::Ui::BadgeComponent.new(label: "Default"))

      def warn = render(Admin::Ui::BadgeComponent.new(label: "NO ALT", tone: :warn))

      def accent = render(Admin::Ui::BadgeComponent.new(label: "MCP", tone: :accent))

      def marked
        render(Admin::Ui::BadgeComponent.new(label: "Blog post").with_mark_content('<span class="size-1.5 rounded-full bg-cat-1"></span>'.html_safe))
      end
    end
  end
end
