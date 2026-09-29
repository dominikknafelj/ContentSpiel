module ContentBlocks
  # Creates or updates a content block (spec §7.2): the same translate-then-
  # assign shape as `Posts::Save`/`Pages::Save`, plus the append-on-create
  # rule a brand new block's `position` needs.
  #
  # Permissions: `<owner>.edit` (and `<owner>.publish` on a published
  # owner) -- see `ContentBlocks::OwnerPermissions`. A block's owner never
  # changes through here, so the check runs once, before anything is
  # assigned.
  #
  # An image block's library image (media library design spec §5.1):
  # `media_asset_id` in `attributes` sets, changes or (nil/"") clears it --
  # CS Studio's image field after a pick in the media picker, or Duplicate
  # copying the source's. Choosing one also needs `media.upload` and
  # an existing asset (`Media::Choosing`), so a duplicate of an image block
  # does too. Every save then refreshes the block's `media_usages` rows
  # (its image and its rich-text body's images) inside the transaction.
  class Save < ApplicationService
    include OwnerPermissions
    include Media::Choosing

    TRANSLATED = %i[caption alt body].freeze

    def initialize(block, attributes: {}, translations: {}, actor: Current.actor)
      @block = block
      @attributes = attributes.to_h.symbolize_keys
      @translations = translations.to_h
      @actor = actor
    end

    def call
      refused = owner_refusal(@block.owner) { |key| authorize!(key, @block) }
      return denied(refused, @block) if refused

      image_refusal = media_choice_result(@block, :media_asset_id, :image)
      return image_refusal if image_refusal

      saved = ContentBlock.transaction do
        assign
        @block.save || raise(ActiveRecord::Rollback)
        Media::UsageIndex.refresh(@block)

        created = @block.previously_new_record?
        changes = Audit::Snapshot.field_changes_for(@block)
        record_event(created ? "block.created" : "block.updated", subject: @block, field_changes: changes) if created || changes.any?
        true
      end

      return failure(@block) unless saved

      success(@block)
    end

    private

    def assign
      # `block_type` is assigned first: `settings`/`assign_settings` below
      # both need it to know which type's schema they're casting against.
      # `media_asset_id` is an image block's library image, already
      # checked by `#media_choice_result` (see the class comment).
      @block.assign_attributes(@attributes.slice(:block_type, :media_asset_id, :position))

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
