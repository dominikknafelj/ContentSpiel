# The whole folder tree, read once (`FolderTree.load`: one query) and answered
# from memory: a site holds at most Media::Folder::MAX_FOLDERS folders, so the
# column, the move dialog and the services' depth checks all walk this and
# never ask the database per folder. Siblings are in natural order: case
# ignored, a run of digits compared as a number ("event 2" before "Event 10").
class Media::FolderTree
  Node = Data.define(:id, :parent_id, :name)

  def self.load
    new(Media::Folder.pluck(:id, :parent_id, :name).map { |row| Node.new(*row) })
  end

  def initialize(nodes)
    @by_id = nodes.index_by(&:id)
    @children = nodes.group_by(&:parent_id).transform_values { |siblings| siblings.sort_by { |node| order_key(node.name) } }
  end

  def size = @by_id.size

  def ids = @by_id.keys

  def find(id) = @by_id[id]

  def roots = @children.fetch(nil, [])

  def children(id) = @children.fetch(id, [])

  # Top first, ending at the folder itself; empty for an id that is not here.
  def path(id)
    nodes = []
    node = find(id)
    while node
      nodes.unshift(node)
      node = find(node.parent_id)
    end
    nodes
  end

  def path_name(id) = path(id).map(&:name).join(" / ")

  # A top folder is 1.
  def depth(id) = path(id).size

  # A folder with no folder in it is 1.
  def height(id) = 1 + children(id).map { |node| height(node.id) }.max.to_i

  def descendant_ids(id)
    children(id).flat_map { |node| [ node.id, *descendant_ids(node.id) ] }
  end

  # A folder is inside itself.
  def inside?(id, of:) = id == of || path(id).any? { |node| node.id == of }

  # Every folder with its depth, a folder before its children, siblings in order.
  def each_in_order(&block)
    return enum_for(:each_in_order) unless block

    walk(roots, 1, &block)
  end

  private

  def walk(nodes, depth, &block)
    nodes.each do |node|
      yield node, depth
      walk(children(node.id), depth + 1, &block)
    end
  end

  def order_key(name)
    name.downcase.split(/(\d+)/).map { |part| part.match?(/\A\d+\z/) ? [ 0, part.to_i ] : [ 1, part ] }
  end
end
