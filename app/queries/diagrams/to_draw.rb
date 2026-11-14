module Diagrams
  # The Diagram blocks a person may save whose stored drawing is not of their
  # current source, one row per language that has a source of its OWN
  # (draw-diagrams spec §3): the list CS Studio's "Draw diagrams" task draws,
  # and the count System status shows for the same viewer.
  #
  # A row's `state` is `:not_drawn` (no drawing the site could show) or
  # `:kept` (a drawing of another source, which the site keeps showing until
  # the new one is saved). A language whose source is blank is no row even
  # when it shows another language's by fallback: it has nothing to draw
  # until a person writes a source of its own. Only the languages switched on
  # count. Blocks of trashed pages hide here, as in every list (there is no
  # `default_scope`), and a page outside the viewer's scope is not found.
  #
  # Whether the viewer may SAVE a row is the save's own rule, asked without
  # writing (`Editing::Rights`, which is `AccessControl::OwnerRule` through
  # `AccessControl.allowed?`): `pages.edit`, and `pages.publish` on a page
  # that is published or scheduled.
  #
  # Order: the page tree's (`TreeOrder` among siblings, depth first), then
  # the block's place on its page (a section's blocks at the section's own
  # place, by column and position), then Settings' language order.
  class ToDraw
    Row = Data.define(:block, :page, :locale, :state, :source)

    def initialize(actor:)
      @actor = actor
    end

    def rows = @rows ||= build

    def count = rows.size

    # `[page, rows]` for each page with a row, in tree order.
    def pages = rows.group_by(&:page).to_a

    private

    def build
      languages = Locales.enabled
      blocks = diagram_blocks.to_a
      return [] if blocks.empty?

      pages = blocks.map(&:owner).uniq(&:id).select { |page| Editing::Rights.missing(@actor, page).nil? }.index_by(&:id)
      rank = tree_rank
      blocks.select { |block| pages.key?(block.owner_id) }
        .sort_by { |block| [ rank.fetch(block.owner_id, rank.size), place(block), block.id ] }
        .flat_map { |block| rows_of(block, pages.fetch(block.owner_id), languages) }
    end

    def diagram_blocks
      readable = AccessControl.scope(@actor, "pages.read", Page.all, channel: :admin)
      ContentBlock.where(owner_type: "Page", owner_id: readable.select(:id), block_type: BlockTypes.fetch(:diagram).name)
        .includes(:owner, :section)
    end

    # Each page's turn in a depth-first walk of the kept tree.
    def tree_rank
      children = Page.kept.pluck(:id, :parent_id, :position).group_by { |_, parent_id, _| parent_id }
      rank = {}
      walk = lambda do |parent_id|
        children.fetch(parent_id, []).sort_by { |id, _, position| TreeOrder.key(position, id) }.each do |id, _, _|
          rank[id] = rank.size
          walk.call(id)
        end
      end
      walk.call(nil)
      rank
    end

    # Where a block sits on its page: a section's blocks at their section's
    # place, then by column and position within it.
    def place(block)
      top = block.section || block
      [ top.position.to_i, top.id, block.section ? block.section_column.to_i : 0, block.position.to_i ]
    end

    def rows_of(block, page, languages)
      stored = block.translated_settings.to_h
      languages.filter_map do |code|
        source = stored.dig(code, "source")
        next if source.blank?

        state = state_of(stored.dig(code, "drawing"), source)
        Row.new(block: block, page: page, locale: code, state: state, source: source) if state
      end
    end

    # nil for a drawing of this very source that the site can show.
    def state_of(stored, source)
      return :not_drawn unless stored.is_a?(Hash) && stored["svg"].is_a?(String) && stored["svg"].present?

      drawing = Drawing.new(stored)
      return :not_drawn if drawing.reason
      :kept unless drawing.current?(source)
    end
  end
end
