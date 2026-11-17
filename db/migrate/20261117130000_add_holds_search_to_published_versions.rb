# Whether a copy holds a Search block (`holds_search`), written when the copy
# is taken, as `lists_posts` is: `SiteSearch::SearchPage` (the page a
# theme's header search box points at, `ThemeHelper#search_page`, asked on
# every public page whose theme draws that box) and `SiteSearch::TagPage`
# found the holders by testing `blocks @> '[{"block_type":"search"}]'`,
# which no index serves, so Postgres read and decompressed the `blocks` of
# every copy ever taken, the history included, before it kept the current
# ones: a scan that grew with every publish (about 44 ms a page on a site
# republished many times). The flag is read instead, from the pages that
# ever held one (the partial index), and no `blocks` is read at all.
#
# The backfill is SQL with no application class: `:search` is a capability
# only a built-in may claim (`BlockTypeDefinition#refuse_outside!`), and the
# built-in Search block, named `search`, is the one type that claims it.
class AddHoldsSearchToPublishedVersions < ActiveRecord::Migration[8.1]
  def up
    add_column :published_versions, :holds_search, :boolean, null: false, default: false
    mark_search_holders
    add_index :published_versions, %i[record_type record_id], where: "holds_search", name: "index_published_versions_holding_search"
  end

  def down
    remove_column :published_versions, :holds_search
  end

  # Public so that the test can run it.
  def mark_search_holders
    execute(<<~SQL.squish) # sql: a frozen backfill on the table as it is at this version, naming no model
      UPDATE published_versions SET holds_search = TRUE
      WHERE record_type = 'Page' AND blocks @> '[{"block_type":"search"}]'::jsonb
    SQL
  end
end
