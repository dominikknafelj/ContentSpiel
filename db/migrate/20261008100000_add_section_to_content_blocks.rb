# A block points at its section (sections spec §3.1): `section_id` names a
# block of a container type on the same page, `section_column` the 1-based
# column it sits in; both are null for a top-level block, and `position` is
# counted per container. The foreign key is the default NO ACTION, like the
# keys to `media_assets` (`MediaForeignKeysNoAction` says why not RESTRICT):
# a section that still holds a block can't be deleted around
# `ContentBlocks::Destroy`.
class AddSectionToContentBlocks < ActiveRecord::Migration[8.1]
  def change
    add_reference :content_blocks, :section, null: true, index: false, foreign_key: { to_table: :content_blocks }
    add_column :content_blocks, :section_column, :integer
    add_check_constraint :content_blocks, "(section_id IS NULL) = (section_column IS NULL)", name: "content_blocks_section_and_column_together"
    add_check_constraint :content_blocks, "section_column IS NULL OR section_column >= 1", name: "content_blocks_section_column_from_one"
    add_index :content_blocks, %i[section_id section_column position], name: "index_content_blocks_on_section_and_column_and_position"
  end
end
