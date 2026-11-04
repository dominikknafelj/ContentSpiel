module Admin
  module Ui
    # A row of tabs that are plain links, drawn as the posts list's
    # segmented control (design pass round 3, handoff §4.9): the current one
    # inverted and `aria-current="page"`, the others meta words. A tab change
    # is a navigation. Used by the Trash screen's type tabs (each with its
    # count) and a form's Form | Submissions (forms plan, Task 5).
    #
    # `tabs` is a list of `{ label:, href:, current:, count: nil }`; `label`
    # the `<nav>`'s accessible name. Anything else for the links (`data`)
    # comes in as `link_data`.
    class TabLinksComponent < AdminComponent
      LINK_CLASS = "inline-flex items-center gap-1.5 border-r border-line px-3 py-1.5 text-sm last:border-r-0".freeze

      def initialize(tabs:, label:, link_data: {})
        @tabs = tabs
        @label = label
        @link_data = link_data
      end

      def render? = @tabs.any?

      private

      attr_reader :tabs, :label, :link_data

      def link_class(current)
        "#{LINK_CLASS} #{current ? "bg-ink font-semibold text-paper" : "text-meta hover:bg-sunken"}"
      end
    end
  end
end
