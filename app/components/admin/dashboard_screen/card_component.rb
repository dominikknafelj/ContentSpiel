module Admin
  module DashboardScreen
    # One of the dashboard's three cards (design pass round 2, Task 16): a
    # small mono heading with a "→" link to the fuller list, then at most
    # `LIMIT` rows -- or, with none, an in-card empty state, so an empty card
    # is the same card. Each card is its own `<section>` labelled by its
    # heading, so a screen reader names every list.
    #
    # The rows are slots (`with_row`), whatever the caller renders for them;
    # the card only caps them (`LIMIT`, `limit:` for another cap, `limit: nil` for
    # none -- the activity feed, whose own query already limits it), so a list that returns more can't
    # grow the card. `hint:` is one muted line under the rows ("Schedule a
    # draft to see it here."), for a list that is short; `link:` is the
    # `[path, label]` of the "→" (nil when the viewer has no fuller list to
    # open).
    class CardComponent < Admin::AdminComponent
      LIMIT = 5

      renders_many :rows

      def initialize(title:, id:, empty:, link: nil, hint: nil, limit: LIMIT)
        @limit = limit
        @title = title
        @id = id
        @empty = empty
        @link = link
        @hint = hint
      end

      def visible_rows = limit ? rows.first(limit) : rows.to_a

      private

      attr_reader :title, :id, :empty, :link, :hint, :limit
    end
  end
end
