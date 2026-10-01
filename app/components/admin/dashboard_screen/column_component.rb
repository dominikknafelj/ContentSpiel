module Admin
  module DashboardScreen
    # One titled dashboard list (dashboard spec §4.2-§4.4): its rows, or --
    # when it's empty -- the one sentence the spec gives it instead of an
    # empty box, plus a "Show all" link only where a fuller filtered list
    # exists (`show_all_path`, nil otherwise). Its own `<section>` is
    # labelled by its heading (`id:`), so a screen reader's landmark list
    # names each list, not five anonymous regions.
    #
    # `feed` is the `Dashboard::Feed` the rows came from, asked for each
    # row's `#last_change` -- the first ask loads every list's newest events
    # in one batch, so it costs nothing per row. `time:` is handed through
    # to every row (`RowComponent`'s own comment).
    class ColumnComponent < Admin::AdminComponent
      def initialize(title:, id:, records:, empty:, feed:, show_all_path: nil, time: :updated_at)
        @title = title
        @id = id
        @records = records
        @empty = empty
        @feed = feed
        @show_all_path = show_all_path
        @time = time
      end

      private

      attr_reader :title, :id, :records, :empty, :feed, :show_all_path, :time
    end
  end
end
