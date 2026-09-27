module Admin
  # Inline block editing in the page editor (cs-studio spec §5.1/§6.1,
  # Task 5): each block card is its own autosaving form (`update`), plus
  # `create` (the block picker, at the end or between two cards),
  # `destroy`, `reorder` (drag or Move up/down) and `duplicate`. Every
  # action is scoped to one page's own blocks (`set_page` + `@page.
  # content_blocks`), never a bare `ContentBlock.find` -- a block has no
  # meaning outside the page it's on, and this is what keeps one editor
  # from PATCHing a block that belongs to a page they don't have open.
  class ContentBlocksController < BaseController
    include AutosaveResponses
    include FileParams

    # Which schema-declared settings fields and `uses_columns` a save
    # actually writes to depends on the block's own registered type (spec
    # §5.1's split rule) -- there is no fixed allowlist to hang beside
    # `Admin::PagesController`'s own `TRANSLATED_FIELDS`/`ATTRIBUTE_FIELDS`,
    # since a different block on the same page can have an entirely
    # different schema. `TRANSLATED_COLUMNS`/`ATTRIBUTE_COLUMNS` below are
    # the one thing that *is* fixed: which of the columns a type can `uses`
    # at all are translated (Mobility/ActionText) versus a plain attribute
    # (the attachment) -- `block.definition.uses_columns` still gates which
    # of these a given type's own params are actually read from.
    TRANSLATED_COLUMNS = %w[caption alt body].freeze
    ATTRIBUTE_COLUMNS = %w[image].freeze

    GONE_MESSAGE = "This block was deleted"

    before_action :set_page

    # The block picker (spec §5.1): `params[:after_id]`, when present, is
    # which existing block this new one was added *below* -- read here, not
    # folded into `params[:block]`, since it's this controller's own
    # insertion instruction, not a column `ContentBlocks::Save` assigns.
    def create
      block = @page.content_blocks.new
      result = ContentBlocks::Save.call(block, attributes: { block_type: params.dig(:block, :block_type) })

      if result.ok?
        reposition_after(result.record, params[:after_id])
        render turbo_stream: insertion_stream(result.record, params[:after_id]), status: :created
      else
        render turbo_stream: picker_error_stream(result.errors), status: :unprocessable_entity
      end
    end

    # The block card's own autosave endpoint (spec §6.1) -- same shape as
    # `Admin::PagesController#update`: PATCHes on every field's `input`
    # (debounced) or `focusout`, answers with the shared Turbo Stream
    # response regardless of success. A block that no longer exists (an
    # editor's tab still open on a card another tab already deleted) 410s
    # with a fixed status message (spec §5.1's "Interfaces" list) rather
    # than raising `RecordNotFound` -- there is no per-field slot left in
    # the DOM to blame, only the status line's own wording.
    def update
      block = @page.content_blocks.find_by(id: params[:id])
      return render_gone unless block

      attributes, translations = split_block_params(block)
      attributes = drop_blank_file_params(attributes, fields: ATTRIBUTE_COLUMNS)
      attributes[:image] = nil if !attributes.key?(:image) && ActiveModel::Type::Boolean.new.cast(params.dig(:block, :remove_image))
      image_changing = attributes.key?(:image)

      result = ContentBlocks::Save.call(block, attributes: attributes, translations: { admin_locale => translations })

      streams = autosave_stream(
        record: result.record,
        result: result,
        status_id: Admin::BlockCardComponent.error_prefix(block) + "-save-status",
        error_prefix: Admin::BlockCardComponent.error_prefix(block),
        base_updated_at: params[:base_updated_at],
        fields: block_error_fields(block)
      )

      streams << image_field_stream(result.record) if result.ok? && image_changing

      render turbo_stream: streams, status: (result.ok? ? :ok : :unprocessable_entity)
    end

    # Permanent (spec §7's "No trash" interim state) -- the card simply
    # disappears from the list, no confirmation round trip beyond the
    # `ConfirmDialogComponent` the card's own "⋯" menu already gated this
    # request behind client-side.
    def destroy
      block = @page.content_blocks.find_by(id: params[:id])
      return render_gone unless block

      ContentBlocks::Destroy.call(block)
      render turbo_stream: turbo_stream.remove(ActionView::RecordIdentifier.dom_id(block))
    end

    # Drag reorder or Move up/down (spec §6.1): the client already knows
    # the complete new order (a drop event's own DOM order, or a client-side
    # swap before this same request) -- `ContentBlocks::Reorder` just checks
    # it names exactly this page's blocks and writes it out. Answers with
    # the status only (spec §5.1's "Interfaces" list): unlike a card's own
    # autosave, a reorder touches no field with its own error slot to
    # refresh.
    def reorder
      result = ContentBlocks::Reorder.call(@page, params[:ids])
      status_id = "content-blocks-status"

      state = result.ok? ? Admin::SaveStatusComponent.new(id: status_id, state: :saved, at: Time.current) :
        Admin::SaveStatusComponent.new(id: status_id, state: :error, count: result.errors.size)

      render turbo_stream: turbo_stream.replace(status_id, state), status: (result.ok? ? :ok : :unprocessable_entity)
    end

    # Duplicate (spec §5.1): copies the type, its settings (both halves --
    # untranslated and every locale's translations), every locale's
    # caption/alt/body and the image attachment (reusing the same blob
    # rather than re-uploading it), then inserts the copy directly after the
    # source the same way `create`'s own `after_id` does -- `after_id:
    # source.id` here is always present, unlike `create`'s (which is only
    # sometimes given), so this never falls back to appending at the end.
    def duplicate
      source = @page.content_blocks.find_by(id: params[:id])
      return render_gone unless source

      copy = @page.content_blocks.new(block_type: source.block_type, settings: source.settings, translated_settings: source.translated_settings)
      copy_translations(source, copy)

      result = ContentBlocks::Save.call(copy, attributes: {})
      return render(turbo_stream: [], status: :unprocessable_entity) unless result.ok?

      copy.image.attach(source.image.blob) if source.image.attached?
      reposition_after(copy, source.id)
      render turbo_stream: turbo_stream.after(ActionView::RecordIdentifier.dom_id(source), block_card_component(copy.reload)), status: :created
    end

    private

    def set_page
      @page = Page.find(params[:page_id])
    end

    def block_card_component(block)
      Admin::BlockCardComponent.new(page: @page, block: block, locale: admin_locale, url_options: admin_url_options)
    end

    # Splits `params[:block]` by the exact rule spec §5.1 lays out: schema
    # fields with `translated?` go to `translations[locale][:settings]`,
    # the rest to `attributes[:settings]`; `caption`/`alt`/`body` are
    # translated columns, `image` is a plain attribute -- every one of
    # those gated by whether this block's own type actually `uses` that
    # column at all, the same allowlist reasoning
    # `Admin::PagesController::ATTRIBUTE_FIELDS` uses for its own record.
    def split_block_params(block)
      block_params = params.fetch(:block, ActionController::Parameters.new)
      definition = block.definition

      attributes = {}
      translations = {}

      if definition && block_params.key?(:settings)
        settings = block_params[:settings].to_unsafe_h
        normalize_group_fields(settings, definition)

        plain, translated = split_settings(settings, definition)
        attributes[:settings] = plain
        translations[:settings] = translated
      end

      uses = definition&.uses_columns || []
      TRANSLATED_COLUMNS.each { |column| translations[column.to_sym] = block_params[column] if uses.include?(column) && block_params.key?(column) }
      ATTRIBUTE_COLUMNS.each { |column| attributes[column.to_sym] = block_params[column] if uses.include?(column) && block_params.key?(column) }

      [ attributes, translations ]
    end

    # A `groups` field's raw params need straightening into an ordered
    # Array before `ContentBlock#assign_settings` ever sees them -- see
    # `Admin::FieldParams`'s own comment. No built-in block type declares
    # one yet, so this is a no-op today; it's here so the first one that
    # does gets it for free.
    def normalize_group_fields(settings, definition)
      definition.fields.select { |field| field.type == :groups }.each do |field|
        key = field.name
        settings[key] = Admin::FieldParams.normalize(settings[key]) if settings.key?(key)
      end
    end

    def split_settings(settings, definition)
      plain, translated = {}, {}

      definition.fields.each do |field|
        next unless settings.key?(field.name)

        (field.translated? ? translated : plain)[field.name] = settings[field.name]
      end

      [ plain, translated ]
    end

    # `fields:` for `Admin::AutosaveResponses#autosave_stream` -- every
    # schema field's error lives under the dotted `"settings.<name>"` key
    # `ContentBlock#settings_are_valid` reports it against (its own
    # comment explains why); every `uses_columns` entry reports directly
    # under its own bare name, same as `Admin::PagesController`'s own
    # column fields.
    def block_error_fields(block)
      definition = block.definition
      return {} unless definition

      fields = definition.fields.each_with_object({}) { |field, hash| hash[field.name] = [ "settings.#{field.name}" ] }
      definition.uses_columns.each_with_object(fields) { |column, hash| hash[column] = [ column ] }
    end

    # Appends `block.id` right after `after_id` in the page's current block
    # order, then persists that through `ContentBlocks::Reorder` -- shared
    # by `create`'s "add between two cards" and `duplicate`'s "insert right
    # after the source". A blank `after_id` (the end-of-list picker, or a
    # `create` with none given) leaves the block exactly where
    # `ContentBlocks::Save#assign_position` already appended it, so there's
    # nothing here to do.
    def reposition_after(block, after_id)
      return if after_id.blank?

      ordered = @page.content_blocks.reload.order(:position).pluck(:id)
      ordered.delete(block.id)
      index = ordered.index(after_id.to_i)
      ordered.insert(index ? index + 1 : ordered.length, block.id)
      ContentBlocks::Reorder.call(@page, ordered)
    end

    # Where the new card's own Turbo Stream lands: right after the card it
    # was added below (the between-cards picker), or appended to the list
    # (the end-of-list picker, or a stale/blank `after_id`).
    def insertion_stream(block, after_id)
      after_block = after_id.present? ? @page.content_blocks.find_by(id: after_id) : nil

      if after_block
        turbo_stream.after(ActionView::RecordIdentifier.dom_id(after_block), block_card_component(block))
      else
        turbo_stream.append("content-blocks-list", block_card_component(block))
      end
    end

    def picker_error_stream(errors)
      turbo_stream.replace("content-blocks-alert", partial: "admin/shared/field_errors", locals: { id: "content-blocks-alert", messages: errors })
    end

    # Every locale's caption/alt/body, copied literally (no fallback) from
    # `source` onto `copy` -- `Mobility.with_locale` is what both the
    # reader and the writer need for a translated column (Locales.default
    # note in `ContentBlocks::Save` explains why the writer side can't take
    # a `locale:` keyword directly the way a jsonb reader can).
    def copy_translations(source, copy)
      Locales.enabled.each do |code|
        Mobility.with_locale(code) do
          copy.caption = source.caption
          copy.alt = source.alt
          copy.body = source.body.to_s if source.body.present?
        end
      end
    end

    # The Turbo Stream `update`/`destroy`/`duplicate` answer with for a
    # block that's already gone (spec §5.1's "Interfaces" list: "A PATCH to
    # a destroyed block answers 410 with the status 'This block was
    # deleted'") -- there's no card left in the DOM to replace a save-status
    # line inside of, so this targets a fixed id every page editor renders
    # once, up front (`content-blocks-alert`), the same slot a failed
    # `create` also reports into.
    def render_gone
      render turbo_stream: turbo_stream.replace("content-blocks-alert",
        partial: "admin/shared/field_errors", locals: { id: "content-blocks-alert", messages: [ GONE_MESSAGE ] }), status: :gone
    end

    def image_field_stream(block)
      prefix = Admin::BlockCardComponent.error_prefix(block)

      turbo_stream.replace("#{prefix}-image-section", partial: "admin/shared/hero_image_field", locals: {
        section_id: "#{prefix}-image-section",
        image_id: "#{prefix}-image", image_html_name: "block[image]",
        image_value: block.image,
        checkbox_id: "#{prefix}-remove_image", checkbox_html_name: "block[remove_image]",
        show_checkbox: block.image.attached?
      })
    end
  end
end
