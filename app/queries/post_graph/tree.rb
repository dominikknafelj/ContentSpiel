# The page tree as far as THIS viewer can read it (pages in the mind graph,
# spec §1, §2), from `(id, parent_id, position)` rows the caller has already
# narrowed by the read scope. No statement and no record: the graph needs a
# page's place in tree order, its depth and its readable neighbours for two
# hundred pages at once, and closure_tree would ask per page.
#
# WHAT IS NOT AMONG THE ROWS DOES NOT EXIST HERE. A page whose parent the
# viewer cannot read has no parent (so no tree line is drawn to it and its
# id is never handed out), stands at depth 1 and comes after the tree proper
# in `order`, by id. Home is the one page with no `parent_id` (were there
# ever two, the one of the lowest id); when it is not among the rows there is
# no `home_id`.
#
# Siblings are ordered by `position`, one without a position after those
# with one, then by id: the order the Pages screen and the public menu show.
# The key is `PublicSite::Branch#in_tree_order`'s, written out here as it is
# in `Admin::PagesScreen::TreeNodeComponent#children` and
# `Admin::EditorScreen::NewPageFormComponent#choices`, because those three
# sort records and this sorts ids (`test/queries/post_graph/tree_test.rb`
# holds the two against each other).
module PostGraph
  class Tree
    attr_reader :order, :home_id

    def initialize(rows)
      @parent = {}
      position = {}
      rows.each do |id, parent_id, place|
        @parent[id] = parent_id
        position[id] = place
      end
      @children = {}
      @parent.each { |id, parent_id| (@children[parent_id] ||= []) << id if @parent.key?(parent_id) }
      @children.each_value { |ids| ids.sort_by! { |id| [ position[id].nil? ? 1 : 0, position[id].to_i, id ] } }
      @home_id = @parent.filter_map { |id, parent_id| id if parent_id.nil? }.min
      @order = []
      @depth = {}
      roots = @parent.keys.select { |id| parent(id).nil? }.sort_by { |id| [ id == @home_id ? 0 : 1, id ] }
      roots.each { |id| visit(id, id == @home_id ? 0 : 1) }
      @rank = @order.each_with_index.to_h
    end

    def parent(id) = @parent.key?(@parent[id]) ? @parent[id] : nil
    def children(id) = @children.fetch(id, [])
    def neighbours(id) = [ parent(id), *children(id) ].compact
    def depth(id) = @depth.fetch(id)
    def rank(id) = @rank.fetch(id)

    private

    def visit(id, depth)
      @order << id
      @depth[id] = depth
      children(id).each { |child| visit(child, depth + 1) }
    end
  end
end
