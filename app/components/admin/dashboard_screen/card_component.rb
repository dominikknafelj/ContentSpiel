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
    # grow the card. `link:` is the `[path, label]` of the "→" (nil when the
    # viewer has no fuller list to open).
    #
    # With no rows the card says `empty` as one quiet line in dim, left-aligned
    # where the first row would be (Claude Design's O6), and not with
    # `Admin::Ui::EmptyStateComponent` (a centred bold title in 48px of padding;
    # its 16 other uses stay as they are, layout points spec decision 12). The
    # `empty_action` slot is drawn after that line, only while the card has no rows.
    #
    # Two optional slots in the header, for the notes cards (notes spec §5):
    # `badge` stands beside the title (a count: "3 new", a total) and
    # `action` before the "→" ("Mark all read"). A card that fills neither is
    # drawn exactly as before. `footer` is a line under the rows, for a card
    # whose way to the fuller list is said in words there ("All notes for
    # you →") instead of by the header's arrow; a card passes one or the
    # other.
    class CardComponent < Admin::AdminComponent
      LIMIT = 5

      renders_many :rows
      renders_one :badge
      renders_one :action
      renders_one :footer
      # Drawn after the empty line, only while the card has no rows: a link, which the caller builds.
      renders_one :empty_action

      def initialize(title:, id:, empty:, link: nil, limit: LIMIT)
        @limit = limit
        @title = title
        @id = id
        @empty = empty
        @link = link
      end

      def visible_rows = limit ? rows.first(limit) : rows.to_a

      private

      attr_reader :title, :id, :empty, :link, :limit
    end
  end
end
