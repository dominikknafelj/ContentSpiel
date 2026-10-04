module Admin
  # Inline block editing in the page editor (cs-studio spec §5.1/§6.1,
  # Task 5): each block card is its own autosaving form (`update`), plus
  # `create` (the "Add block" row at the end of the list),
  # `destroy`, `reorder` (drag or Move up/down) and `duplicate`. Every
  # action is scoped to one page's own blocks (`set_page` + `@page.
  # content_blocks`), never a bare `ContentBlock.find` -- a block has no
  # meaning outside the page it's on, and this is what keeps one editor
  # from PATCHing a block that belongs to a page they don't have open.
  class ContentBlocksController < BaseController
    include AutosaveResponses
    include MediaFields

    # Which schema-declared settings fields and `uses_columns` a save
    # actually writes to depends on the block's own registered type (spec
    # §5.1's split rule) -- there is no fixed allowlist to hang beside
    # `Admin::PagesController`'s own `TRANSLATED_FIELDS`/`ATTRIBUTE_FIELDS`,
    # since a different block on the same page can have an entirely
    # different schema. `TRANSLATED_COLUMNS`/`ATTRIBUTE_COLUMNS` below are
    # the one thing that *is* fixed: which of the columns a type can `uses`
    # at all are translated (Mobility) versus a plain attribute -- the
    # image, whose column (`uses :image`) is saved as `media_asset_id`, the
    # id the image field's hidden input (`Admin::Columns
    # ::MediaColumnComponent`, media library Task 8) sends after a pick,
    # or "" after Remove -- `block.definition.uses_columns` still gates
    # which of these a given type's own params are actually read from.
    #
    # `TRANSLATED_COLUMNS` is derived from `ContentBlocks::Save::TRANSLATED`
    # (fix round 1) rather than a second, hand-kept `%w[caption alt body]`
    # literal -- that service is the one place a translated column actually
    # gets assigned, so this controller's own idea of "which columns are
    # translated" can never drift out of sync with it.
    TRANSLATED_COLUMNS = ContentBlocks::Save::TRANSLATED.map(&:to_s).freeze
    # `uses` column => the param (and attribute) it's sent as.
    ATTRIBUTE_COLUMNS = { "image" => "media_asset_id" }.freeze

    GONE_MESSAGE = "This block was deleted"

    before_action :set_page

    # The "Add block" row (spec §5.1): the new block is appended. `params
    # [:after_id]`, when present, is which existing block this new one goes
    # *below* -- read here, not folded into `params[:block]`, since it's this
    # controller's own insertion instruction, not a column `ContentBlocks
    # ::Save` assigns. No view sends it any more (the between-cards pickers
    # are gone; Duplicate has its own route), but it stays honoured so a
    # client that wants "insert below" has one.
    def create
      block = @page.content_blocks.new
      result = ContentBlocks::Save.call(block, attributes: { block_type: params.dig(:block, :block_type) })

      if result.ok?
        reposition_after(result.record, params[:after_id])
        render turbo_stream: [ *insertion_stream(result.record, params[:after_id]), *page_base_streams ], status: :created
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

      # The block's own base (its `updated_at`), not the page's. A refused
      # save vouches for nothing, so it also streams no page base
      # (`page_base_streams` is only reached on success) -- see
      # `AutosaveResponses#refuse_stale_autosave`.
      return if refuse_stale_autosave(block, status_id: Admin::BlockCardComponent.error_prefix(block) + "-save-status",
        error_prefix: Admin::BlockCardComponent.error_prefix(block),
        reload_url: admin_page_path(@page, **admin_url_options))

      attributes, translations = split_block_params(block)
      stored_asset_id = block.media_asset_id
      result = ContentBlocks::Save.call(block, attributes: attributes, translations: { admin_locale => translations })

      streams = autosave_stream(
        record: result.record,
        result: result,
        status_id: Admin::BlockCardComponent.error_prefix(block) + "-save-status",
        error_prefix: Admin::BlockCardComponent.error_prefix(block),
        fields: without_untouched_media_slot(block_error_fields(block), "image", sent: attributes[:media_asset_id], stored_before: stored_asset_id)
      )

      # A refused image choice puts the field back to the stored image (and
      # shows why) -- see `Admin::MediaFields`.
      refused = refused_media_field_stream(result, attribute: :media_asset_id, error_attribute: :image,
        sent: attributes[:media_asset_id]) do |stored, errors|
        Admin::BlockCardComponent.image_field(block: block, asset: stored, locale: admin_locale, errors: errors)
      end
      streams << refused if refused
      streams.concat(page_base_streams) if result.ok?

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

      render turbo_stream: [ turbo_stream.remove(ActionView::RecordIdentifier.dom_id(block)), *page_base_streams ]
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
    #
    # An Undo toast follows a reorder that changed something: a PATCH to this
    # same action with the order as it was, read here before the service
    # runs. The answer to *that* request (`undo=1`) also re-renders the list
    # (`update`, so the list element itself -- the Sortable container --
    # stays), since unlike a drop the client's DOM isn't already in the
    # order the server now has; and it gets a plain confirmation with no
    # Undo of its own, so two orders can't be bounced between forever.
    def reorder
      before = @page.content_blocks.reorder(:position, :id).ids
      result = ContentBlocks::Reorder.call(@page, params[:ids])
      status_id = "content-blocks-status"

      state = if result.ok? then Admin::SaveStatusComponent.new(id: status_id, state: :saved, at: Time.current)
      elsif result.denied? then Admin::SaveStatusComponent.new(id: status_id, state: :forbidden)
      else Admin::SaveStatusComponent.new(id: status_id, state: :error, count: result.errors.size)
      end

      streams = [ turbo_stream.replace(status_id, state) ]
      if result.ok?
        streams.concat(page_base_streams)
        streams.concat(reorder_undo_streams(before))
      else
        streams << picker_error_stream(result.errors)
      end
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

      copy = @page.content_blocks.new(block_type: source.block_type, settings: source.settings, translated_settings: source.translated_settings)
      copy_translations(source, copy)

      # The image reference goes in through the service (final fix wave,
      # Minor 6), so it's saved in the same authorized, audited write -- and
      # the `block.created` snapshot shows it.
      attributes = source.media_asset_id ? { media_asset_id: source.media_asset_id } : {}
      result = ContentBlocks::Save.call(copy, attributes: attributes)
      return render(turbo_stream: picker_error_stream(result.errors), status: failure_status(result)) unless result.ok?

      reposition_after(copy, source.id)
      render turbo_stream: [ *insertion_stream(copy.reload, source.id), *page_base_streams ], status: :created
    end

    private

    # Through the read scope (access-control design spec §3.3): blocks of a
    # page the actor can't read are a 404, whatever the action -- the page
    # isn't disclosed. Whether they may *change* the blocks of a page they
    # can read is `ContentBlocks::*`'s call (`pages.edit`, plus `publish`
    # on a published page), answered 403 below.
    def set_page
      @page = admin_scope(Page.all).find(params[:page_id])
      # Before any write this request makes touches it -- see
      # `#page_base_streams`.
      @page_updated_at_before_write = @page.updated_at
    end

    # Every successful block write touches the page (`ContentBlocks::Save`,
    # final fix wave I3), which moves the `updated_at` the page settings
    # form on this same screen holds as its autosave base -- so, left
    # alone, that form's next save would report "Changed elsewhere" against
    # nothing but this same editor's block edit.
    #
    # So a block response may move that form's base forward to the page's
    # new `updated_at` -- but only when the base the form holds (sent by
    # `admin--autosave`/`admin--blocks` as `X-Page-Base-Updated-At`) was
    # still current *before* this write (fix round 2). If the page was saved
    # elsewhere since the form loaded it (another tab, another user), the
    # sent base is older than `@page_updated_at_before_write`, and moving it
    # forward would silently absorb that save: the form's next autosave
    # would pass the staleness check and overwrite the other editor's
    # fields without a word. Then the base is left alone, so that autosave
    # still reports "Changed elsewhere". No base sent (an older client), or
    # an unparseable one, means nothing to vouch for -- left alone too.
    def page_base_streams
      return [] unless page_base_was_current?

      id = "#{Admin::PageSettingsFormComponent::ID_PREFIX}-base-updated-at"
      [ turbo_stream.replace(id, partial: "admin/shared/base_updated_at_field",
        locals: { id: id, value: Page.where(id: @page.id).pick(:updated_at).iso8601(6) }) ]
    end

    def page_base_was_current?
      sent = request.headers["X-Page-Base-Updated-At"]
      sent.present? && Time.iso8601(sent) >= @page_updated_at_before_write
    rescue ArgumentError
      false
    end

    def reorder_undo_streams(before)
      return [ blocks_list_stream, toast_stream("Order restored.") ] if params[:undo].present?

      after = @page.content_blocks.reload.reorder(:position, :id).ids
      return [] if after == before

      [ toast_stream("Block order changed.", kind: :undo, action: {
        label: "Undo", method: :patch,
        url: reorder_admin_page_content_blocks_path(@page, ids: before, undo: 1, **admin_url_options)
      }) ]
    end

    # The whole block list, re-rendered in the server's order. The first card
    # has Move up disabled and the last Move down (`first:`/`last:`), as on a
    # page load.
    def blocks_list_stream
      blocks = @page.content_blocks.reload.order(:position).to_a
      cards = blocks.each_with_index.map { |block, index| render_to_string(block_card_component(block, first: index.zero?, last: index == blocks.size - 1)) }
      turbo_stream.update("content-blocks-list", html: helpers.safe_join(cards))
    end

    def failure_status(result) = result.denied? ? :forbidden : :unprocessable_entity

    def block_card_component(block, first: false, last: false)
      Admin::BlockCardComponent.new(page: @page, block: block, locale: admin_locale, url_options: admin_url_options, first: first, last: last)
    end

    # Splits `params[:block]` by the exact rule spec §5.1 lays out: schema
    # fields with `translated?` go to `translations[locale][:settings]`,
    # the rest to `attributes[:settings]`; `caption`/`alt`/`body` are
    # translated columns (`body` the rich-text document JSON), `image` is a
    # plain attribute (`media_asset_id`) -- every one of
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
      ATTRIBUTE_COLUMNS.each { |column, param| attributes[param.to_sym] = block_params[param] if uses.include?(column) && block_params.key?(param) }

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
    # was added below (an `after_id`, which Duplicate always has), or appended
    # to the list (the "Add block" row, or a stale/blank `after_id`).
    #
    # The card is rendered knowing whether it is now first and/or last (its
    # Move up / Move down start disabled accordingly). Its neighbours are not
    # re-rendered: with no between-cards pickers there is nothing else on them
    # to change, and the one thing that does -- the previously-last card's
    # Move down is now enabled -- is corrected in the browser by `admin
    # --blocks#refreshMoveState`, which runs whenever the list's children
    # change. (Re-rendering a neighbour would also throw away whatever its
    # editors held, an unsaved field included.)
    def insertion_stream(block, after_id)
      ordered = @page.content_blocks.reload.order(:position).to_a
      after_block = after_id.present? ? ordered.find { |candidate| candidate.id == after_id.to_i } : nil
      card = block_card_component(block, first: ordered.first&.id == block.id, last: ordered.last&.id == block.id)

      [ after_block ? turbo_stream.after(ActionView::RecordIdentifier.dom_id(after_block), card) : turbo_stream.append("content-blocks-list", card) ]
    end

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
  end
end
