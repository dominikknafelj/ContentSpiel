# A Section's anchor is one name on its page (`ContentBlocks::Save` refuses a
# second under the page's lock); this index is the backstop for a row written
# around the service. It holds sections only and only a present anchor, so
# every other block, and a section with none, is outside it. It inserts no row.
class AddUniqueSectionAnchorToContentBlocks < ActiveRecord::Migration[8.1]
  def change
    add_index :content_blocks, "owner_type, owner_id, ((settings ->> 'anchor'))",
      unique: true, name: "index_content_blocks_on_section_anchor",
      where: "block_type = 'section' AND COALESCE(settings ->> 'anchor', '') <> ''"
  end
end
