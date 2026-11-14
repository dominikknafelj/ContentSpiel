module Admin
  # The Draw diagrams task (draw-diagrams spec §4): `update` saves one Diagram
  # block's drawing for one language, sent by the list's script through the
  # write queue after the renderer frame drew the language's source.
  #
  # The action decides, in this order, and nothing is written or audited
  # before the save:
  #   1. the block, through the read scope (a page outside it, or a block that
  #      is no Diagram, is `gone`, 404);
  #   2. the base: the block changed since the list was drawn (`stale`, 409,
  #      compared as the block card's autosave compares, `Admin::StaleForm`);
  #   3. a hold of the block in ANOTHER tab (`held`, 409, with the holder's
  #      short name). The task takes no claim (`held_elsewhere?`, as an
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
  # save never publishes: on a live page (`live`) the drawing is an
  # unpublished change, which `review_url` opens Publish changes for.
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

    def update
      block = diagram_block or return refuse(:gone, :not_found)
      return refuse(:stale, :conflict) if stale_form?(block, params[:base_updated_at])

      hold = held_elsewhere?(block)
      return refuse(:held, :conflict, holder: hold.user && ::PersonName.of(hold.user)) if hold

      locale = params[:locale].to_s
      return refuse(:changed, :conflict) unless drawn_from_stored_source?(block, locale)

      drawing = { "svg" => text_param(:svg), "from" => text_param(:from) }
      result = ContentBlocks::Save.call(block, translations: { locale => { settings: { "drawing" => drawing } } })
      return refuse(:denied, :forbidden) if result.denied?
      return refuse(drawing_refusal(result.record, locale), :unprocessable_entity) unless result.ok?

      page = block.owner
      render json: { ok: true, live: ::Publishing::State.of(page).live?, page_id: page.id, page_title: page.title,
                     review_url: admin_page_path(page, review: "publish") }
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

    def refuse(reason, status, holder: nil)
      render json: { ok: false, reason: reason.to_s, holder: holder }, status: status
    end
  end
end
