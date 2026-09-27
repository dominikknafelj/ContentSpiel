module ContentBlocks
  # Creates or updates a content block (spec §7.2): the same translate-then-
  # assign shape as `Posts::Save`/`Pages::Save`, plus the append-on-create
  # rule a brand new block's `position` needs.
  class Save < ApplicationService
    TRANSLATED = %i[caption alt body].freeze

    def initialize(block, attributes: {}, translations: {}, actor: Current.actor)
      @block = block
      @attributes = attributes.to_h.symbolize_keys
      @translations = translations.to_h
      @actor = actor
    end

    def call
      authorize!(:save, @block)

      saved = ContentBlock.transaction do
        assign
        @block.save || raise(ActiveRecord::Rollback)
      end

      return failure(@block) unless saved

      record_event(:content_block_saved, block: @block)
      success(@block)
    end

    private

    def assign
      @translations.each do |locale, values|
        Mobility.with_locale(locale) { @block.assign_attributes(values.to_h.symbolize_keys.slice(*TRANSLATED)) }
      end
      @block.assign_attributes(@attributes.slice(:block_type, :settings, :image, :position))
      assign_position
    end

    # Appends to the end of the page's existing blocks when no position was
    # given, on create only: the admin's "add a block" row submits no
    # position at all, and a nil here would otherwise reach Postgres as a
    # raw not-null violation instead of landing in the right spot. Once a
    # block is persisted, its position is only ever moved deliberately,
    # through `ContentBlocks::Reorder`.
    def assign_position
      return unless @block.new_record? && @attributes[:position].nil?

      @block.position = (@block.page.content_blocks.maximum(:position) || -1) + 1
    end
  end
end
