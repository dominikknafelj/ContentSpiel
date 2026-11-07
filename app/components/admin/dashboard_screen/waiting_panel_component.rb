module Admin
  module DashboardScreen
    # "Waiting for you": the records that wait on someone, for an open thread
    # or for changes not on the site yet (`Dashboard::WaitingForYou`), in an
    # action panel inside `turbo-frame#dashboard-waiting`. The frame is the
    # one part `GET dashboard/waiting` answers again
    # (`Admin::DashboardController#waiting`), and its `display: contents`
    # keeps the panel an item of the dashboard's grid.
    #
    # The filter is three links in the panel's head
    # (`Admin::Ui::TabLinksComponent`), each navigating the frame to its
    # filter. The filter shown as current is the query's own, so an unknown
    # one reads as Everything, as the query reads it. The filter is the
    # frame's `src` and never the page's address: a live note reloads the
    # frame's `src` (`admin--notes--inbox#reload`), which keeps the choice.
    # After a press, and only then, the focus goes to the filter now current
    # (`admin--dashboard--waiting`), since the answer replaces the pressed
    # link.
    #
    # Beside the heading, a neutral count of every record waiting under the
    # filter (`Dashboard::WaitingForYou#total`), so a sixth one is not
    # invisible; nothing at zero, where the empty line speaks. Never accent:
    # it is everybody's work, not what is unread for the viewer. Every row
    # is a `WaitingRowComponent`; the empty line says what the filter found
    # nothing of.
    class WaitingPanelComponent < Admin::AdminComponent
      FRAME = "dashboard-waiting".freeze

      def initialize(waiting:)
        @waiting = waiting
      end

      private

      attr_reader :waiting

      def filter = waiting.filter

      # `turbo_prefetch: false`: a filter's address is the frame's `src`
      # once pressed, and Turbo answers ANY GET of an address it prefetched
      # in the last 10 seconds with that prefetch, the live reload's
      # (`frame.reload()`) included. The pointer rests on the link it
      # pressed, which the answer draws anew under it, so Turbo prefetches
      # the current filter right after the press; a note arriving in those
      # 10 seconds then redrew the rows from before it, and nothing else
      # would correct them.
      def filter_data
        { turbo_frame: FRAME, turbo_prefetch: false, action: "turbo:click->admin--dashboard--waiting#press", "admin--dashboard--waiting-target": "filter" }
      end

      def tabs
        Dashboard::WaitingForYou::FILTERS.map do |name|
          { label: t(".filters.#{name}"), href: helpers.admin_dashboard_waiting_path(filter: name, **url_options), current: name == filter }
        end
      end

      # `admin_url_options` is a controller helper, absent when a component
      # is rendered on its own (a component test).
      def url_options = helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options : {}
    end
  end
end
