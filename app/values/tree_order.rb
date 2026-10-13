# THE ORDER OF A PAGE'S CHILDREN, the one rule: by position, a page without
# one LAST, then by id. It is Postgres' own order for `ORDER BY position, id`
# (a NULL sorts last), which is what closure_tree's `order: "position"` gives
# the public menu and the subpage list, so a list sorted here in Ruby reads
# as one the database sorted.
#
# WHO ASKS: everything that holds the tree as one loaded list and sorts the
# siblings itself. The public branch of a theme's sidebar
# (`PublicSite::Branch`), CS Studio's page tree
# (`Admin::PagesScreen::TreeNodeComponent#children`), the "Inside" list of
# the New page dialog (`Admin::EditorScreen::NewPageFormComponent#choices`)
# and the mind graph's tree (`PostGraph::Tree`, which sorts ids from plain
# rows and so takes the key and not the sort).
#
# WHY IT IS A VALUE OF ITS OWN. The key was written four times, each copy
# with a comment naming the others, and twice a copy was wrong: the Pages
# screen sorted by the bare column and raised for a row without a position
# (a 500 for the whole screen), and the New page dialog sorted by
# `position.to_i`, which puts such a row FIRST where every other list put it
# last. A row without a position is a half-written one (the column takes
# NULL; `Pages::Move` and closure_tree number every page they place), so it
# is rare, and a second writing fails nothing until the day it is met.
# `test/values/tree_order_test.rb` holds the rule, that it is the database's
# order, and that the key is written in this file and nowhere else in `app`
# or `lib`.
#
# TWO LIMITS, both older than this file. (1) Pages of ONE position are
# ordered by id here; closure_tree's own lists (`order: "position"`: the
# public menu, `page.children`) name no tie-break, so for two siblings with
# one position their order is the database's choice and can differ from
# this. Positions are unique among siblings wherever the services wrote
# them. (2) This is the one writing of the order in RUBY. SQL says the same
# order as `order(:position, :id)` in `Page::TreeRanking`,
# `Admin::TreeController` and `Admin::GroupsScreen::BranchTree`.
#
# NOT THE ORDER OF THE WHOLE TREE: this orders siblings. Depth first over
# them is each caller's own walk.
module TreeOrder
  module_function

  # What a sibling is sorted by, from its position and its id.
  def key(position, id) = [ position.nil? ? 1 : 0, position.to_i, id ]

  # Records that answer `position` and `id`, in the tree's order; a new list.
  def sort(pages) = pages.sort_by { |page| key(page.position, page.id) }
end
