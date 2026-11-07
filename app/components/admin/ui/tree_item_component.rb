module Admin
  module Ui
    # One row of a tree of the site's pages, the one row both trees draw:
    # Pages renders it, and the mind graph's list reads its classes
    # (`CLASSES`, handed to the script as `data-tree-classes`) and builds the
    # same markup. The nesting around it (`<ul>`/`<li>` in Pages, the
    # treeitems of the graph's list) is the screen's, and so are the title's
    # link and every extra in the slots.
    #
    # Its look is the `.admin-tree` block of `content-spiel.tailwind.css` and
    # its lengths the four `--cs-tree-*` of `content-spiel.css`: every value
    # of `CLASSES` is a class of that block, never a utility, and a screen
    # hands the row no class of its own (`data:` with a `class` key is
    # refused), so both trees cannot drift apart.
    #
    # `parent:` draws the disclosure, a button saying whether the branch is
    # open (`aria-expanded`) and naming the list it folds (`controls:`, the
    # children list's id); a leaf keeps the disclosure's empty box so the
    # marks line up, and `flat:` draws neither (the graph's posts, tags and
    # post types). The button's press is `admin--tree--disclosure#toggle`, the
    # controller the tree it stands in carries, which folds the branch and
    # writes the open set. `folded:` is what the server drew; the script
    # toggles it after.
    #
    # `with_add` draws the row's "+", a part of the row like the disclosure:
    # the screen hands it only its name, the address it opens and its
    # behaviour hooks, never a class. It rests transparent and shows as the
    # handle does, never by the selection.
    #
    # `path:` is the page's address, for a find that starts with "/"
    # (`data-tree-path`), and `node_id:` the bare page id (`data-tree-id`).
    # `data:` is merged onto the row for the screen's behaviour hooks.
    class TreeItemComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "A row inside the screen's own nesting: a parent's disclosure is a button that says whether its branch is open and names the list it folds, its name Fold or Unfold with the title; the glyphs are silent to a screen reader; what rests out of sight is clipped, never removed, so a screen reader still hears it.",
        motion: :reduced,
        content_edges: %i[short long],
        widths: :fluid,
        interface: %i[id title parent folded controls selected context_only flat root path node_id data],
        limits: [
          "Its disclosure folds nothing by itself: the tree's script answers its press and writes the open set.",
          "A long title is cut to one line, the whole title in its tooltip; a title never wraps.",
          "It draws one row and never its nesting: the list around it, and the step between levels, are the screen's markup on the tree's own classes."
        ],
        states: %i[rest hover focus selected folded open leaf context_only flat root],
        keys: %w[fold unfold],
        slots: %i[handle mark title state trailings add],
        controller: nil,
        keyboard: [ "test/system/admin/tree_test.rb", "a row's disclosure folds and unfolds its branch by mouse and by keyboard" ]
      )

      # The class names of the `.admin-tree` block, by part and state.
      CLASSES = {
        tree: "admin-tree",
        row: "admin-tree-row",
        row_selected: "admin-tree-row--selected",
        row_context_only: "admin-tree-row--context-only",
        row_flat: "admin-tree-row--flat",
        disclosure: "admin-tree-row__disclosure",
        mark: "admin-tree-row__mark",
        title: "admin-tree-row__title",
        state: "admin-tree-row__state",
        trailing: "admin-tree-row__trailing",
        count: "admin-tree-row__count",
        reveal: "admin-tree-row__reveal",
        add: "admin-tree-row__add",
        handle: "admin-tree-node__handle",
        children: "admin-tree__children"
      }.freeze

      # The drag handle, in the gutter left of the row.
      renders_one :handle
      # The mark box's content; the page glyph, or the home glyph on the root,
      # when none is given.
      renders_one :mark
      # The link or the label; the component wraps it in the title's box.
      renders_one :title
      # The state dot, 6px after the title, in the state's box.
      renders_one :state
      # Markers, presence, the count and "+", in order, each given with
      # `with_trailing`. The plural name is ViewComponent's: `renders_many
      # :trailing` would make `with_trailing` the setter of the whole list.
      renders_many :trailings
      # The row's "+", last: its name (`label:`), the address it opens
      # (`href:`; a button without one) and the screen's hooks (`data:`).
      renders_one :add, ->(label:, href: nil, data: {}) do
        raise ArgumentError, "the row's + takes no class from its screen: its look is the .admin-tree block's" if data.key?(:class) || data.key?("class")

        glyph = render("admin/shared/tree_glyph", name: :plus)
        if href
          link_to(glyph, href, class: CLASSES[:add], aria: { label: label }, data: data)
        else
          tag.button(glyph, type: "button", class: CLASSES[:add], aria: { label: label }, data: data)
        end
      end

      def initialize(id:, title:, parent: false, folded: false, controls: nil, selected: false, context_only: false, flat: false, root: false, path: nil, node_id: nil, data: {})
        raise ArgumentError, "a tree row takes no class from its screen: its look is the .admin-tree block's" if data.key?(:class) || data.key?("class")
        raise ArgumentError, "a parent's disclosure names the list it folds: give controls:" if parent && !flat && controls.blank?

        @id = id
        @whole_title = title
        @parent = parent
        @folded = folded
        @controls = controls
        @selected = selected
        @context_only = context_only
        @flat = flat
        @root = root
        @path = path
        @node_id = node_id
        @data = data
      end

      def before_render
        raise ArgumentError, "a tree row is given its title's link or label (with_title)" unless title?
      end

      private

      attr_reader :whole_title

      def disclosure? = @parent && !@flat

      # A leaf's disclosure column, kept empty so the marks line up.
      def empty_disclosure? = !@parent && !@flat

      def row_class
        [ CLASSES[:row], (CLASSES[:row_selected] if @selected), (CLASSES[:row_context_only] if @context_only), (CLASSES[:row_flat] if @flat) ].compact.join(" ")
      end

      def row_data
        @data.merge(tree_row: true, tree_title: whole_title, tree_path: @path, tree_id: @node_id).compact
      end

      def disclosure_label = t(@folded ? ".unfold" : ".fold", title: whole_title)

      def default_glyph = @root ? :home : :page
    end
  end
end
