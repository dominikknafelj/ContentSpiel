# One root page, enforced by the database. `Page#only_one_root_page` is a
# validation only (it counts EVERY page with a NULL parent_id, trashed ones
# included, so a trashed root blocks a second one exactly as a kept one does);
# two concurrent creates on an empty site could both pass it. A plain unique
# index on parent_id would never collide (NULLs are distinct), so the index is
# on a constant per root row: the expression is true for every row the partial
# predicate keeps, and a second root is a uniqueness violation.
class AddSingleRootIndexToPages < ActiveRecord::Migration[8.1]
  def change
    add_index :pages, "(parent_id IS NULL)", unique: true, where: "parent_id IS NULL", name: "index_pages_on_single_root"
  end
end
