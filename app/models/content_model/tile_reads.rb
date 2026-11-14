module ContentModel
  # What one render of a block's tile reads of the block, read once.
  #
  # A tile asks its type three times (`summary`, `preview`, `tile_picture`),
  # and a type whose three answers share one costly read (the Diagram block
  # parses its drawing) keeps that read here, by the block object and a key
  # of its own, for as long as the render lasts
  # (`Admin::EditorScreen::TileSummaryComponent#render_in`) and no longer. A
  # block changed in memory between two renders is therefore read again
  # with no key of its contents to compute, and outside a tile's render
  # (a job, the console, a test calling the type) nothing is kept.
  module TileReads
    KEY = :content_model_tile_reads

    def self.during
      outer = ActiveSupport::IsolatedExecutionState[KEY]
      ActiveSupport::IsolatedExecutionState[KEY] = {}.compare_by_identity
      yield
    ensure
      ActiveSupport::IsolatedExecutionState[KEY] = outer
    end

    # The block's read under `key` in this render, else the block's answer.
    def self.fetch(block, key)
      kept = ActiveSupport::IsolatedExecutionState[KEY]
      return yield unless kept

      reads = (kept[block] ||= {})
      reads.key?(key) ? reads[key] : (reads[key] = yield)
    end
  end
end
