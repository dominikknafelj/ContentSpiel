module Admin
  module Ui
    # A row of tabs that are plain links, drawn as one framed segmented
    # control: the current one an ink segment with paper words at 600 and
    # `aria-current="page"`, the others dim words that go sunken under the
    # pointer, a line rule between segments. A tab change is a navigation.
    # Used by the Notes filter, Waiting for you's filter, the Trash screen's
    # type tabs (each with its count) and a form's Form | Submissions.
    # Focus is a 2px accent outline inside the segment; on the current one,
    # where the accent is too faint on ink in dark, a paper ring 4px inside it.
    #
    # `tabs` is a list of `{ label:, href:, current:, count: nil }`; `label`
    # the `<nav>`'s accessible name. Anything else for the links (`data`)
    # comes in as `link_data`.
    class TabLinksComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "A navigation named by its label, of links with the current one aria-current=page; a tab change is a navigation.",
        motion: :none,
        content_edges: %i[many short],
        widths: :fluid,
        interface: %i[tabs label link_data],
        limits: [
          "It draws links only, never a tablist: pressing one is a visit.",
          "With no tabs it renders nothing."
        ],
        states: %i[rest with_counts hover focus],
        keys: [],
        slots: [],
        controller: nil,
        keyboard: [ "test/system/admin/keyboard_navigation_test.rb", "a tab link is a Tab stop, and Enter on it goes to its tab, which the links mark current" ]
      )

      LINK_CLASS = "inline-flex items-center gap-1.5 border-r border-line px-3 py-1.5 text-sm last:border-r-0 focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-accent".freeze

      def initialize(tabs:, label:, link_data: {})
        @tabs = tabs
        @label = label
        @link_data = link_data
      end

      def render? = @tabs.any?

      private

      attr_reader :tabs, :label, :link_data

      def link_class(current)
        "#{LINK_CLASS} #{current ? "bg-ink font-semibold text-paper focus-visible:inset-ring-4 focus-visible:inset-ring-paper" : "text-dim hover:bg-sunken"}"
      end
    end
  end
end
