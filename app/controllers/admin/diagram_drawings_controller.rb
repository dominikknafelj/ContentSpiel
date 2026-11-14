module Admin
  # The Draw diagrams task (draw-diagrams spec §3 to §5): `index` lists every
  # Diagram block the viewer may save whose stored drawing is not of its
  # current source (`Diagrams::ToDraw`), drawn by
  # `Admin::DiagramDrawingsScreen::ListComponent`, and `update` saves one Diagram
  # block's drawing for one language, sent by the list's script through the
  # write queue after the renderer frame drew the language's source.
  #
  # `update` decides, in this order, and nothing is written or audited
  # before the save:
  #   1. the block, through the read scope (a page outside it, or a block that
  #      is no Diagram, is `gone`, 404);
  #   2. the base: the block changed since the list was drawn (`stale`, 409,
  #      compared as the block card's autosave compares, `Admin::StaleForm`);
  #   3. a hold of the block in ANOTHER tab (`held`, 409, with the holder's
  #      short name, or `own_tab` and no name when the other tab is the
  #      viewer's own, which the script says in the hold strip's sentence).
  #      The task takes no claim (`held_elsewhere?`, as an
  #      instant action asks), so a person who opens the card a moment later
  #      is not held off by it;
  #   4. `from`, the digest of the source the frame drew, against the
  #      language's stored source (`changed`, 409): the source changed in
  #      between, or the language has none of its own;
  #   5. the save, `ContentBlocks::Save` with the language's translated
  #      settings in the shape the block card sends, so the drawing is
  #      cleaned, size-checked, permission-checked (`denied`, 403) and audited
  #      as a card's save is. A drawing that does not clean is `too_large`
  #      (over either of the frame's two limits) or `invalid_drawing`, 422.
  #
  # The answer is JSON, not a Turbo Stream: the list draws its own row
  # states, and each `reason` is a key its script reads a sentence for. A
  # save never publishes: on a page with a published copy, live or
  # scheduled (`published`, `Publishing::State#published?`), the drawing is
  # an unpublished change that the copy does not carry, so a scheduled page
  # goes live without it; `review_url` opens Publish changes for it, and
  # `status` ("live" or "scheduled") is the chip the end-of-run card shows. A
  # saved answer carries the block's new base (`base`, as the rows write
  # it), which the script hands the block's rows in its other languages:
  # without it the next language's save is refused as stale by this one.
  class DiagramDrawingsController < BaseController
    include StaleForm
    include EditingClaims

    # The cleaning reasons that are the frame's limits (`Diagrams::Drawing`'s
    # MAX_BYTES and MAX_ELEMENTS, `Admin::DiagramRenderersController::LIMITS`).
    LIMIT_REASONS = %w[too_large too_many_elements].freeze

    # JSON whatever the request accepts, so the 403 of `require_permission`
    # is JSON too (`BaseController#forbidden!`).
    before_action(only: :update) { request.format = :json }
    before_action { require_permission("pages.edit") }

    def index
      @to_draw = ::Diagrams::ToDraw.new(actor: Current.actor)
    end

    def update
      block = diagram_block or return refuse(:gone, :not_found)
      return refuse(:stale, :conflict) if stale_form?(block, params[:base_updated_at])

      hold = held_elsewhere?(block)
      return refuse_held(hold) if hold

      locale = params[:locale].to_s
      return refuse(:changed, :conflict) unless drawn_from_stored_source?(block, locale)

      drawing = { "svg" => text_param(:svg), "from" => text_param(:from) }
      result = ContentBlocks::Save.call(block, translations: { locale => { settings: { "drawing" => drawing } } })
      return refuse(:denied, :forbidden) if result.denied?
      return refuse(drawing_refusal(result.record, locale), :unprocessable_entity) unless result.ok?

      page = block.owner
      state = ::Publishing::State.of(page)
      render json: { ok: true, published: state.published?, status: state.status, page_id: page.id, page_title: page.title,
                     review_url: admin_page_path(page, review: "publish"), base: result.record.updated_at.iso8601(6) }
    end

    private

    # A Diagram block of a page in the actor's read scope (trashed pages are
    # outside it), or nil.
    def diagram_block
      ContentBlock.find_by(id: params[:id], owner_type: Page.polymorphic_name, owner_id: admin_scope(Page.all).select(:id),
        block_type: BlockTypes.fetch(:diagram).name)
    end

    # The frame drew this language's own stored source: a language switched
    # off, or with no source of its own, has nothing to draw.
    def drawn_from_stored_source?(block, locale)
      return false unless Locales.enabled?(locale)

      source = block.translated_settings.to_h.dig(locale, "source")
      source.present? && text_param(:from) == ::Diagrams::Drawing.digest(source)
    end

    # The save's own refusal of the drawing: its cast keeps the cleaning's
    # reason in the block's unsaved settings (`ContentModel::FieldTypes`,
    # `DRAWING_REFUSED`), which only the error key `:invalid_drawing` names.
    # Any other error is the drawing's too: it is the one field sent.
    def drawing_refusal(block, locale)
      reason = block.translated_settings.to_h.dig(locale, "drawing", ContentModel::FieldTypes::DRAWING_REFUSED)
      LIMIT_REASONS.include?(reason) ? :too_large : :invalid_drawing
    end

    def text_param(name) = (value = params[name]).is_a?(String) ? value : nil

    # The viewer's own other tab is named as such, never by their own name.
    def refuse_held(hold)
      return refuse(:held, :conflict, own_tab: true) if hold.user_id == Current.user.id

      refuse(:held, :conflict, holder: hold.user && ::PersonName.of(hold.user))
    end

    def refuse(reason, status, holder: nil, own_tab: false)
      body = { ok: false, reason: reason.to_s, holder: holder }
      body[:own_tab] = true if own_tab
      render json: body, status: status
    end
  end
end
