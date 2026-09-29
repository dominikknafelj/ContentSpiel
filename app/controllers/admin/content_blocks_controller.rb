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
    # at all are translated (Mobility) versus a plain attribute
    # (the attachment) -- `block.definition.uses_columns` still gates which
    # of these a given type's own params are actually read from.
    #
    # `TRANSLATED_COLUMNS` is derived from `ContentBlocks::Save::TRANSLATED`
    # (fix round 1) rather than a second, hand-kept `%w[caption alt body]`
    # literal -- that service is the one place a translated column actually
    # gets assigned, so this controller's own idea of "which columns are
    # translated" can never drift out of sync with it.
    TRANSLATED_COLUMNS = ContentBlocks::Save::TRANSLATED.map(&:to_s).freeze
    ATTRIBUTE_COLUMNS = %w[image].freeze

    GONE_MESSAGE = "This block was deleted"

    before_action :set_page

    # The block picker (spec §5.1): `params[:after_id]`, when present, is
    # which existing block this new one was added *below* -- read here, not
    # folded into `params[:block]`, since it's this controller's own
    # insertion instruction, not a column `ContentBlocks::Save` assigns.
    def create
      block = @page.content_blocks.new
      previous_last_id = last_block_id
      result = ContentBlocks::Save.call(block, attributes: { block_type: params.dig(:block, :block_type) })

      if result.ok?
        reposition_after(result.record, params[:after_id])
        render turbo_stream: insertion_stream(result.record, params[:after_id], previous_last_id: previous_last_id), status: :created
      else
        render turbo_stream: picker_error_stream(result.errors), status: failure_status(result)
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
      # An image upload goes into the library first and the block is saved
      # pointing at the new asset -- the same interim path, and the same
      # "a refused upload is a failed save" rule, as the page hero
      # (`Admin::PagesController#update`'s own comment); Task 8's picker
      # replaces it.
      attributes = drop_blank_file_params(attributes, fields: ATTRIBUTE_COLUMNS)
      upload = attributes.delete(:image)
      removing = upload.nil? && ActiveModel::Type::Boolean.new.cast(params.dig(:block, :remove_image))
      image_changing = upload.present? || removing

      if upload
        uploaded = upload_to_library(upload, record: block, field: :image)
        upload_failure = uploaded unless uploaded.ok?
        attributes[:media_asset_id] = uploaded.record.id if uploaded.ok?
      elsif removing
        attributes[:media_asset_id] = nil
      end

      result = upload_failure || ContentBlocks::Save.call(block, attributes: attributes, translations: { admin_locale => translations })

      streams = autosave_stream(
        record: result.record,
        result: result,
        status_id: Admin::BlockCardComponent.error_prefix(block) + "-save-status",
        error_prefix: Admin::BlockCardComponent.error_prefix(block),
        base_updated_at: params[:base_updated_at],
        fields: block_error_fields(block)
      )

      # Re-rendered after a successful image change, and after *any*
      # upload whatever the save's outcome, so the file input never keeps
      # a file the next autosave would upload again (fix round 1, I1) --
      # see `Admin::PagesController#update`.
      if result.ok? && image_changing
        streams << image_field_stream(block, result.record.media_asset)
      elsif upload
        streams.insert(1, image_field_stream(block, Media::Asset.find_by(id: block.attribute_in_database("media_asset_id"))))
      end

      render turbo_stream: streams, status: autosave_status(result)
    end

    # Permanent (spec §7's "No trash" interim state) -- the card simply
    # disappears from the list, no confirmation round trip beyond the
    # `ConfirmDialogComponent` the card's own "⋯" menu already gated this
    # request behind client-side. A refusal (no `pages.edit` -- a view-only
    # editor never shows the menu, so a stale tab or a forged request) or
    # any other failure leaves the card in place and says why in the
    # page's alert slot, instead of removing a card whose block still
    # exists.
    def destroy
      block = @page.content_blocks.find_by(id: params[:id])
      return render_gone unless block

      result = ContentBlocks::Destroy.call(block)
      return render(turbo_stream: picker_error_stream(result.errors), status: failure_status(result)) unless result.ok?

      render turbo_stream: turbo_stream.remove(ActionView::RecordIdentifier.dom_id(block))
    end

    # Drag reorder or Move up/down (spec §6.1): the client already knows
    # the complete new order (a drop event's own DOM order, or a client-side
    # swap before this same request) -- `ContentBlocks::Reorder` just checks
    # it names exactly this page's blocks and writes it out. Answers with
    # the status only (spec §5.1's "Interfaces" list): unlike a card's own
    # autosave, a reorder touches no field with its own error slot to
    # refresh.
    #
    # A failure also says why in the page's alert slot, and a refusal is a
    # 403 with the "no permission" status -- the order already on screen is
    # the client's optimistic one, so leaving it unexplained would look
    # saved.
    def reorder
      result = ContentBlocks::Reorder.call(@page, params[:ids])
      status_id = "content-blocks-status"

      state = if result.ok? then Admin::SaveStatusComponent.new(id: status_id, state: :saved, at: Time.current)
      elsif result.denied? then Admin::SaveStatusComponent.new(id: status_id, state: :forbidden)
      else Admin::SaveStatusComponent.new(id: status_id, state: :error, count: result.errors.size)
      end

      streams = [ turbo_stream.replace(status_id, state) ]
      streams << picker_error_stream(result.errors) unless result.ok?
      render turbo_stream: streams, status: (result.ok? ? :ok : failure_status(result))
    end

    # Duplicate (spec §5.1): copies the type, its settings (both halves --
    # untranslated and every locale's translations), every locale's
    # caption/alt/body and the image reference (the copy shows the same
    # library asset -- media library Task 4; nothing is copied, and the
    # asset can't be deleted while either block uses it), then
    # inserts the copy directly after the source the same way `create`'s
    # own `after_id` does -- `after_id: source.id` here is always present,
    # unlike `create`'s (which is only sometimes given), so this never
    # falls back to appending at the end.
    def duplicate
      source = @page.content_blocks.find_by(id: params[:id])
      return render_gone unless source

      previous_last_id = last_block_id
      copy = @page.content_blocks.new(block_type: source.block_type, settings: source.settings, translated_settings: source.translated_settings)
      copy_translations(source, copy)

      # The image reference goes in through the service (final fix wave,
      # Minor 6), so it's saved in the same authorized, audited write -- and
      # the `block.created` snapshot shows it.
      attributes = source.media_asset_id ? { media_asset_id: source.media_asset_id } : {}
      result = ContentBlocks::Save.call(copy, attributes: attributes)
      return render(turbo_stream: picker_error_stream(result.errors), status: failure_status(result)) unless result.ok?

      reposition_after(copy, source.id)
      render turbo_stream: insertion_stream(copy.reload, source.id, previous_last_id: previous_last_id), status: :created
    end

    private

    # Through the read scope (access-control design spec §3.3): blocks of a
    # page the actor can't read are a 404, whatever the action -- the page
    # isn't disclosed. Whether they may *change* the blocks of a page they
    # can read is `ContentBlocks::*`'s call (`pages.edit`, plus `publish`
    # on a published page), answered 403 below.
    def set_page
      @page = admin_scope(Page.all).find(params[:page_id])
    end

    def failure_status(result) = result.denied? ? :forbidden : :unprocessable_entity

    def block_card_component(block, last: false)
      Admin::BlockCardComponent.new(page: @page, block: block, locale: admin_locale, url_options: admin_url_options, last: last)
    end

    # Splits `params[:block]` by the exact rule spec §5.1 lays out: schema
    # fields with `translated?` go to `translations[locale][:settings]`,
    # the rest to `attributes[:settings]`; `caption`/`alt`/`body` are
    # translated columns (`body` the rich-text document JSON), `image` is a plain attribute -- every one of
    # those gated by whether this block's own type actually `uses` that
    # column at all, the same allowlist reasoning
    # `Admin::PagesController::ATTRIBUTE_FIELDS` uses for its own record.
    def split_block_params(block)
      block_params = params.fetch(:block, ActionController::Parameters.new)
      definition = block.definition

      attributes = {}
      translations = {}

      if definition && (block_params.key?(:settings) || block_params[:groups_present].present?)
        settings = block_params.key?(:settings) ? block_params[:settings].to_unsafe_h : {}
        apply_missing_groups(settings, definition, block_params[:groups_present])
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

    # A `groups` field with every row removed sends no key of its own at all
    # -- there's nothing left to name (finding 2, final-fixes round) -- which
    # would otherwise read identically to "this form never touched this
    # field," leaving whatever was last saved untouched instead of emptied.
    # `Admin::Fields::GroupsField`'s own hidden `groups_present` marker
    # (rendered once per groups field, regardless of row count) is what
    # tells the two apart: every name listed there is a groups field this
    # form *did* render, so a missing key for it means "saved as empty," not
    # "not part of this request." Mirrors `Admin::PostsController`'s own
    # `apply_missing_groups` exactly; duplicated rather than shared for the
    # same reason `normalize_group_fields` already is on both controllers
    # (see that method's own comment on `Admin::PostsController`).
    def apply_missing_groups(hash, definition, groups_present)
      present = Array(groups_present).map(&:to_s)

      definition.fields.select { |field| field.type == :groups && present.include?(field.name) }.each do |field|
        hash[field.name] = [] unless hash.key?(field.name)
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
    #
    # `previous_last_id:` (final-fixes round, finding 10) is whichever
    # block was last *before* this insertion (`create`/`duplicate`'s own
    # `last_block_id`, read before either one creates anything) -- needed to
    # know whether this insertion just bumped that card out of last place.
    # `Admin::BlockCardComponent#last?` (whether a card renders its own
    # trailing "+" between-picker, or leaves that slot to the page's
    # always-present end-of-list one) is baked into each card's markup at
    # render time, not recomputed by the browser -- so the newly inserted
    # card has to be told directly whether it's the new last one (`new_
    # last_id`, freshly read off the database now that `reposition_after`
    # has already run), and whichever card *was* last has to be re-rendered
    # too the moment that's no longer it, or it would stay stuck showing no
    # "+" of its own for the rest of this editing session.
    def insertion_stream(block, after_id, previous_last_id: nil)
      ordered = @page.content_blocks.reload.order(:position).to_a
      new_last_id = ordered.last&.id
      after_block = after_id.present? ? ordered.find { |candidate| candidate.id == after_id.to_i } : nil

      new_card_stream = if after_block
        turbo_stream.after(ActionView::RecordIdentifier.dom_id(after_block), block_card_component(block, last: block.id == new_last_id))
      else
        turbo_stream.append("content-blocks-list", block_card_component(block, last: block.id == new_last_id))
      end

      [ new_card_stream, *stale_last_card_stream(ordered, previous_last_id, new_last_id) ]
    end

    # The one extra stream `insertion_stream` needs whenever an insertion
    # bumped the previously-last card out of last place: re-rendered with
    # `last: false` so it picks up the trailing "+" between-picker it's now
    # missing. Nothing to do when there was no previous last card (an empty
    # page's very first block), or the last card didn't actually change (a
    # `create`/`duplicate` inserted strictly before it, e.g. a between-cards
    # picker click on anything but the last card).
    def stale_last_card_stream(ordered, previous_last_id, new_last_id)
      return [] if previous_last_id.nil? || previous_last_id == new_last_id

      previous_last_block = ordered.find { |candidate| candidate.id == previous_last_id }
      return [] unless previous_last_block

      [ turbo_stream.replace(ActionView::RecordIdentifier.dom_id(previous_last_block), block_card_component(previous_last_block, last: false)) ]
    end

    # `reorder`, not `order`: `Page#content_blocks` already carries its own
    # default `-> { order(:position) }` scope, and a plain `.order(...)`
    # only *appends* to an association's existing order rather than
    # replacing it -- so `.order(position: :desc)` here would have quietly
    # produced `ORDER BY position ASC, position DESC` (the first clause
    # already fully determining the result, making the second a no-op) and
    # still handed back the *first* block, not the last one.
    def last_block_id = @page.content_blocks.reorder(position: :desc).pick(:id)

    def picker_error_stream(errors)
      turbo_stream.replace("content-blocks-alert", partial: "admin/shared/field_errors", locals: { id: "content-blocks-alert", messages: errors })
    end

    # Every locale's translated columns (`ContentBlocks::Save::TRANSLATED`
    # -- fix round 1, same one source `TRANSLATED_COLUMNS` above derives
    # from), copied literally (no fallback) from `source` onto `copy` --
    # `Mobility.with_locale` is what both the reader and the writer need for
    # a jsonb column (Locales.default note in `ContentBlocks::Save` explains
    # why the writer side can't take a `locale:` keyword directly the way a
    # jsonb reader can).
    #
    # `body` is the rich-text JSON document (tiptap spec §3.1), copied as
    # data through `body_document`/`assign_body` rather than the Mobility
    # reader/writer pair the other columns use: `assign_body` is the one
    # writer that refuses a "nothing" value instead of silently deleting the
    # locale (`HasRichTextBody#assign_body`). A document is copied verbatim, so a
    # duplicate's body is exactly the source's, and duplicating a duplicate
    # stays that way (the ActionText-era bug this method used to guard
    # against -- a re-rendered `trix-content` wrapper nesting itself on
    # every duplicate -- has no equivalent for plain JSON). A blank locale
    # is skipped rather than copied as an empty document.
    def copy_translations(source, copy)
      Locales.enabled.each do |code|
        Mobility.with_locale(code) do
          ContentBlocks::Save::TRANSLATED.each do |column|
            if column == :body
              document = source.body_document(locale: code)
              copy.assign_body(document, locale: code) unless document.blank?
            else
              copy.public_send("#{column}=", source.public_send(column))
            end
          end
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

    # `asset` is the image to show (or nil) -- after a failed save the
    # block still holds the unsaved reference, so the caller passes the
    # stored one.
    def image_field_stream(block, asset)
      prefix = Admin::BlockCardComponent.error_prefix(block)

      turbo_stream.replace("#{prefix}-image-section", partial: "admin/shared/hero_image_field", locals: {
        section_id: "#{prefix}-image-section", name: "image",
        image_id: "#{prefix}-image", image_html_name: "block[image]",
        image_value: asset&.file,
        checkbox_id: "#{prefix}-remove_image", checkbox_html_name: "block[remove_image]",
        show_checkbox: asset.present?
      })
    end
  end
end
