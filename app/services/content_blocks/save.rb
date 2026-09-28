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
      # `block_type` is assigned first: `settings`/`assign_settings` below
      # both need it to know which type's schema they're casting against.
      @block.assign_attributes(@attributes.slice(:block_type, :image, :position))

      @block.assign_settings(@attributes[:settings], locale: Locales.default) if @attributes.key?(:settings)

      @translations.each do |locale, values|
        values = values.to_h.symbolize_keys
        Mobility.with_locale(locale) { @block.assign_attributes(values.slice(*TRANSLATED).except(:body)) }
        # A rich-text JSON document, Hash or JSON String -- see the same line
        # in `Posts::Save#assign` for why it bypasses `assign_attributes`.
        @block.assign_body(values[:body], locale: locale) if values.key?(:body)
        @block.assign_settings(values[:settings], locale: locale) if values.key?(:settings)
      end

      assign_position
    end

    # Appends to the end of the owner's existing blocks when no position was
    # given, on create only: the admin's "add a block" row submits no
    # position at all, and a nil here would otherwise reach Postgres as a
    # raw not-null violation instead of landing in the right spot. Once a
    # block is persisted, its position is only ever moved deliberately,
    # through `ContentBlocks::Reorder`.
    def assign_position
      return unless @block.new_record? && @attributes[:position].nil?

      @block.position = (@block.owner.content_blocks.maximum(:position) || -1) + 1
    end
  end
end
