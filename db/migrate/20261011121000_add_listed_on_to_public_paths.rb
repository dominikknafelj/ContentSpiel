# The page that gives a post its address (Task 4b of the drafts plan): a
# post's current row says which page's list its path runs through. Until now
# that was worked out again by every writer that needed to know "which posts
# could this page's change have moved", each from a before-picture of its
# own; recorded, it is one query on this table (`PublicSite::Paths.refresh`).
# NULL on a page's row and on every redirect.
#
# No foreign key: `public_paths` is derived, its `record_id` has none either,
# and a page deleted for good loses its posts' rows through the sync of its
# own trashing, not through a constraint.
#
# Filled from the rows themselves, with no application class: a post's path
# is its host's path plus one segment, and a current path is unique in its
# language, so the host is the page that holds the path above.
class AddListedOnToPublicPaths < ActiveRecord::Migration[8.1]
  def up
    add_column :public_paths, :listed_on_id, :bigint
    add_index :public_paths, :listed_on_id, where: "current AND listed_on_id IS NOT NULL", name: "index_public_paths_on_listed_on"
    fill
  end

  def fill
    execute(<<~SQL.squish)
      UPDATE public_paths AS post SET listed_on_id = page.record_id
      FROM public_paths AS page
      WHERE post.record_type = 'Post' AND post.current
        AND page.record_type = 'Page' AND page.current AND page.locale = post.locale
        AND page.path = COALESCE(NULLIF(regexp_replace(post.path, '/[^/]*$', ''), ''), '/')
    SQL
  end

  def down
    remove_column :public_paths, :listed_on_id
  end
end
