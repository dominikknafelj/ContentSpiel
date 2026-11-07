module Admin
  module DashboardScreen
    # One of the dashboard's panels: a head that says the panel's job (its
    # heading and one line under it), tinted by the panel's kind, then at most
    # `LIMIT` rows -- or, with none, one empty line in the panel, so an empty
    # panel is the same panel. Each panel is its own `<section>` labelled by
    # its heading, so a screen reader names every list.
    #
    # The kind says what a panel is for, and its head's colours follow it:
    # `:action` (something waits on the viewer: `--cs-head-action`),
    # `:shortcuts` (a way back into work: `--cs-head-cool`) and `:information`
    # (what is happening: `--cs-head-warm`). The colours are stylesheet rules
    # on `.admin-dashboard-panel--<kind>` (`content-spiel.tailwind.css`), not
    # utilities, so a later rule changes them by plain cascade. The heading
    # and the line take the head's ink; nothing in the head sets its own
    # colour but a badge.
    #
    # The heading and the line are the caller's words, already translated:
    # this component holds none of its own.
    #
    # The rows are slots (`with_row`), whatever the caller renders for them;
    # the panel only caps them (`LIMIT`, `limit:` for another cap, `limit: nil`
    # for none: the activity feed, whose own query already limits it), so a
    # list that returns more cannot grow the panel. `layout: :tiles` lays the
    # rows out as tiles (`ul.admin-draft-tiles`, Pick up where you left
    # off's) instead of ruled rows; each tile draws its own card. `link:` is
    # the `[path, label]` of the "→" (nil when the viewer has no fuller list
    # to open).
    #
    # With no rows the panel says `empty` as one quiet line in dim,
    # left-aligned where the first row would be. It is
    # `Admin::Ui::EmptyStateComponent`'s look drawn by hand, because the
    # panel's action is a link inside the line, not under it. The
    # `empty_action` slot is drawn after that line, only while the panel has
    # no rows.
    #
    # Two optional slots in the head: `badge` stands beside the heading (Notes
    # for you's "3 new") and `action` before the "→" (Notes for you's "Mark
    # all read", Waiting for you's filter). `footer` is a
    # line under the rows, for a panel whose way to the fuller list is said in
    # words there ("All notes for you →") instead of by the head's arrow; a
    # panel passes one or the other.
    class PanelComponent < Admin::AdminComponent
      LIMIT = 5
      KINDS = %i[action shortcuts information].freeze
      LAYOUTS = %i[rows tiles].freeze

      renders_many :rows
      renders_one :badge
      renders_one :action
      renders_one :footer
      # Drawn after the empty line, only while the panel has no rows: a link, which the caller builds.
      renders_one :empty_action

      def initialize(kind:, title:, line:, id:, empty:, link: nil, limit: LIMIT, layout: :rows)
        raise ArgumentError, "unknown kind #{kind.inspect}" unless KINDS.include?(kind)
        raise ArgumentError, "unknown layout #{layout.inspect}" unless LAYOUTS.include?(layout)

        @kind = kind
        @title = title
        @line = line
        @id = id
        @empty = empty
        @link = link
        @limit = limit
        @layout = layout
      end

      def visible_rows = limit ? rows.first(limit) : rows.to_a

      def panel_class = "admin-dashboard-panel admin-dashboard-panel--#{kind}"

      def tiles? = layout == :tiles

      private

      attr_reader :kind, :title, :line, :id, :empty, :link, :limit, :layout
    end
  end
end
