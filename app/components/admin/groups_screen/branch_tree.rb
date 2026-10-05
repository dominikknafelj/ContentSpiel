module Admin
  module GroupsScreen
    # The page tree a `pages.*` row's scope editor offers (access-control design
    # spec §5, round 3 Task 10), loaded ONCE for the whole editor and shared by
    # its six pages rows. A plain object, not a component: it renders nothing.
    #
    # What the viewer sees comes from `AccessControl.tree_visibility`: the pages
    # they can read (`readable`, each with a box) and the unreadable ancestors
    # that are only the path to one (`context_only`, greyed text with no box --
    # titles an actor sees today). A stored branch root that is in neither is
    # not in the tree at all, and so is never given a place in it: it is carried
    # as a hidden input (`PermissionRowComponent`), its position undisclosed.
    #
    # `states(selected_ids)` is the tri-state, server-rendered so the form is
    # correct with scripts off and `admin--branch-picker` only has to keep it
    # so:
    #
    # - `:chosen`   a stored branch root: a ticked box that is submitted;
    # - `:implied`  below a chosen page, so covered by it: a greyed tick,
    #               DISABLED, never submitted (a `page_ids` scope matches a root
    #               and everything below it);
    # - `:partial`  an ancestor of a chosen page, itself neither: shown "-"
    #               (`indeterminate`), unchecked, never submitted;
    # - `:none`.
    #
    # `chosen` is separate from `state` on purpose: a page can be chosen AND
    # implied (a redundant stored root, which the editor never writes itself),
    # and the script must still know it was chosen once the ancestor is unticked.
    class BranchTree
      Node = Data.define(:id, :title, :readable, :parent_id, :child_ids)
      State = Data.define(:state, :chosen, :descendants)

      attr_reader :roots

      def self.for(actor, locale:)
        visibility = AccessControl.tree_visibility(actor)
        visible = visibility[:readable] | visibility[:context_only]
        pages = Page.where(id: visible.to_a).order(:position, :id).to_a
        new(pages: pages, readable: visibility[:readable], context_only: visibility[:context_only], locale: locale)
      end

      def initialize(pages:, readable:, context_only:, locale:)
        @readable = readable.to_set
        visible = @readable | context_only.to_set
        by_parent = pages.group_by { |page| visible.include?(page.parent_id) ? page.parent_id : nil }
        @nodes = pages.to_h do |page|
          [ page.id, Node.new(id: page.id, title: ::Locales.read(page, :title, locale: locale.to_s).presence || "(untitled)",
            readable: @readable.include?(page.id), parent_id: visible.include?(page.parent_id) ? page.parent_id : nil,
            child_ids: by_parent.fetch(page.id, []).map(&:id)) ]
        end
        @roots = by_parent.fetch(nil, []).map(&:id)
      end

      def node(id) = @nodes.fetch(id)
      def include?(id) = @nodes.key?(id)
      def readable?(id) = @readable.include?(id)
      def title(id) = @nodes[id]&.title

      # The stored roots the viewer has no box for -- unreadable, in the tree
      # as context only or not at all. Carried as hidden inputs.
      def unreadable(selected_ids) = selected_ids.reject { |id| readable?(id) }

      def states(selected_ids)
        selected = selected_ids.to_set
        chosen_below = {}
        count = {}
        tally = lambda do |id|
          kids = @nodes[id].child_ids
          kids.each { |kid| tally.call(kid) }
          chosen_below[id] = kids.any? { |kid| selected.include?(kid) || chosen_below[kid] }
          count[id] = kids.sum { |kid| 1 + count[kid] }
        end
        @roots.each { |root| tally.call(root) }

        result = {}
        walk = lambda do |id, covered|
          chosen = selected.include?(id)
          state = if covered then :implied
          elsif chosen then :chosen
          elsif chosen_below[id] then :partial
          else :none
          end
          result[id] = State.new(state: state, chosen: chosen, descendants: count[id])
          @nodes[id].child_ids.each { |kid| walk.call(kid, covered || chosen) }
        end
        @roots.each { |root| walk.call(root, false) }
        result
      end
    end
  end
end
