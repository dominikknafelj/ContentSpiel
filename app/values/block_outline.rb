# A page's blocks in the order a person reads them (sections spec §3.4):
# the top-level blocks by `position`, and inside a section its columns left
# to right, each by `position`. Built from blocks already loaded -- both page
# controllers preload `content_blocks` -- so asking it costs no query, and it
# hands each block its section from the same array, so `block.section`
# costs none either.
class BlockOutline
  def initialize(blocks)
    @blocks = blocks.to_a
    by_id = @blocks.index_by(&:id)
    # Sorted once, here: a section's columns and its blocks are both read
    # from this, several times a render.
    @inside = @blocks.select(&:section_id).sort_by { |block| [ block.section_column, block.position, block.id ] }.group_by(&:section_id)
    @blocks.each { |block| block.association(:section).target = by_id[block.section_id] if by_id.key?(block.section_id) }
  end

  def top_level = @top_level ||= @blocks.reject(&:section_id).sort_by { |block| [ block.position, block.id ] }

  # One array per column of the section's layout; an empty column keeps its
  # place. A block stored beyond the last column is not here (`blocks_in`
  # still lists it): only a layout written around the service leaves one.
  def columns(section)
    by_column = blocks_in(section).group_by(&:section_column)
    Array.new(section.column_count) { |index| by_column.fetch(index + 1, []) }
  end

  # The section's blocks in reading order: column by column, each by
  # `position`.
  def blocks_in(section) = @inside.fetch(section.id, [])

  def reading_order = top_level.flat_map { |block| [ block, *blocks_in(block) ] }
end
