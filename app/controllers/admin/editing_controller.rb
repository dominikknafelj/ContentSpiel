module Admin
  # What an open editor fetches when it is told something changed
  # (live-editing spec §3.2). A class, never `Admin::Editing`, which would
  # shadow `Editing::`.
  #
  # EVERY PART IS FOUND THROUGH THE READ SCOPE and drawn for its viewer as
  # they are now: a record out of scope, in the trash or of a kind with no
  # editor is a 404, and so is a block of another page. The answers are
  # fragments (no layout), fetched with a plain `fetch` the write queue
  # neither holds nor counts, and kept by no cache.
  #
  # A fragment is drawn by the very components, with the very arguments, that
  # `pages/show.html.erb` and `posts/show.html.erb` draw the editor with: the
  # browser swaps one element for the other, so the ids and the marks
  # (`data-editing-unit`, `-subject`, `-part`) have to be the page's own.
  class EditingController < BaseController
    include RecordOfKind
    include AutosaveResponses
    include EditingClaims

    before_action { response.set_header("Cache-Control", "no-store") }
    before_action :set_record

    # The children of `#content-blocks-list`, as the page view draws them.
    def blocks
      raise ActiveRecord::RecordNotFound unless @record.is_a?(Page)

      outline = BlockOutline.new(@record.content_blocks)
      top = outline.top_level
      editable = can_edit?(@record)
      cards = top.each_with_index.map { |block, index| view_context.render(card_for(block, outline:, editable:, first: index.zero?, last: index == top.size - 1)) }
      render html: helpers.safe_join(cards), layout: false
    end

    # One block, as this editor shows it. 204 for a section: its card holds
    # other blocks' forms, so the caller fetches the list. 410 for a block
    # deleted since. With `mark`, the card says who changed it last.
    def block
      raise ActiveRecord::RecordNotFound unless @record.is_a?(Page)

      block = @record.content_blocks.detect { |candidate| candidate.id == params[:block_id].to_i }
      return block_gone if block.nil?

      outline = BlockOutline.new(@record.content_blocks)
      return head(:no_content) if Admin::EditorScreen::SectionCardComponent.draws?(block, outline:)

      editable = can_edit?(@record)
      change = params[:mark] == "1" ? ::Editing::LastChange.for(block, viewer: Current.user) : nil
      render html: helpers.safe_join(parts_of(block, outline:, editable:, change:).map { |part| view_context.render(part) }), layout: false
    end

    # The record's own form: a page's settings, a post's form.
    def record
      form = if @record.is_a?(Page)
        Admin::EditorScreen::PageSettingsFormComponent.new(page: @record, locale: admin_locale, url_options: admin_url_options, holds:)
      else
        Admin::EditorScreen::PostFormComponent.new(post: @record, locale: admin_locale, url_options: admin_url_options, slot_context: {}, form_only: true, holds:)
      end
      render form, layout: false
    end

    # The tab claims a subject ahead of its first save (spec §4.2): sent through
    # the write queue when a clean form gets its first change. 204 when the tab
    # holds the subject now (or sent no tab id: nothing was claimed), 409 with
    # the refusal's streams when another tab holds it.
    def claim
      subject = subject!
      return forbidden! if ::Editing::Rights.missing(Current.actor, @record)
      return refuse_held(subject, **status_ids(subject)) if claim_for(subject, record: @record) == :refused

      head :no_content
    end

    # The tab lets go: a block's form was closed, or the page was left. Deletes
    # only this tab's own row; 204 always for someone who may edit.
    def release
      subject = subject!
      return forbidden! if ::Editing::Rights.missing(Current.actor, @record)

      release_claim(subject, record: @record)
      head :no_content
    end

    # Someone asks for what another tab holds (spec §4.4), or asks again after
    # the pass-over time. Answers `{ state: }`: requested, pending, taken or claimed.
    def take_over = transfer(hand_over: false)

    # The holder's tab, having sent what it held, lets the requester have it.
    # Answers `{ state: }`: handed, or nothing when no request stands or the
    # row is no longer this tab's (`Editing::TakeOver`'s class comment has
    # every combination).
    def hand_over = transfer(hand_over: true)

    # The asking tab leaves (a visit away, the page closing) or stops asking:
    # its own request is cleared, so that the holder's tab does not hand the
    # subject to a tab that is gone. 204 whether or not one stood; the holder
    # is not told and finds `nothing` at its hand-over.
    def withdraw
      subject = subject!
      return forbidden! if ::Editing::Rights.missing(Current.actor, @record)
      return head(:unprocessable_entity) unless Current.editing_tab && Current.user

      ::Editing::Reservation.withdraw(subject:, by: Current.user, tab: Current.editing_tab)
      head :no_content
    end

    private

    def transfer(hand_over:)
      service = ::Editing::TakeOver.new(subject!, record: @record, tab: Current.editing_tab, hand_over:)
      result = service.call
      return forbidden!(result.errors.to_sentence) if result.denied?
      return head(:unprocessable_entity) unless result.ok?

      render json: { state: service.outcome }
    end

    # The block `block_id` names, or the record itself; a block that is not
    # this record's is not found. (A full `def`: `or raise` after an endless one
    # would bind to the definition, not to its body.)
    def subject!
      ::Editing.subject_of(@record, params[:block_id]) or raise ActiveRecord::RecordNotFound
    end

    def status_ids(subject)
      case subject
      when ContentBlock then { status_id: Admin::EditorScreen::BlockCardComponent.status_id(subject), error_prefix: Admin::EditorScreen::BlockCardComponent.error_prefix(subject) }
      when Page then { status_id: "page-save-status", error_prefix: "page" }
      else { status_id: "post-save-status", error_prefix: "post" }
      end
    end

    # The reservations of this record as this viewer's tab sees them, read once
    # for everything this answer draws, as `pages/show.html.erb` does for the page.
    def holds = @holds ||= ::Editing::Holds.on(@record, viewer: Current.user, tab: Current.editing_tab)

    # The record through the read scope, and for a page what its editor reads
    # up front (`Admin::PagesController#show`): the branch once, the hero and
    # the blocks with their images' variants, so the number of statements
    # does not grow with the number of blocks.
    def set_record
      @record = record_of_kind(params[:kind], params[:id])
      return if performed?

      if @record.is_a?(Page)
        AccessControl.preload_branches([ @record ])
        ActiveRecord::Associations::Preloader.new(records: [ @record ], associations: [
          { hero_media_asset: Media::Asset::VARIANT_INCLUDES },
          { content_blocks: { media_asset: Media::Asset::VARIANT_INCLUDES } }
        ]).call
      end
    end

    # A block that is not this page's and one that never existed are a 404; a
    # block this page's audit log says was deleted is a 410, whose body is the
    # notice the hold script shows under the text of someone who was still
    # typing in it (`admin--editing--hold#deleted`): "Dana Weiss deleted this
    # block. Your changes weren't saved." Asked of the event
    # `ContentBlocks::Destroy` writes, which names its page: the block's own,
    # or the section's that took it along (`deleted_block_ids`).
    def block_gone
      deleted = Audit::Event.deleting_block(params[:block_id].to_i, @record.id).order(id: :desc).first
      raise ActiveRecord::RecordNotFound unless deleted

      strip = Admin::EditorScreen::HoldStripComponent.new(subject: ContentBlock.new(id: params[:block_id].to_i), hold: nil, viewer: Current.user,
        kind: :deleted, actor: deleted.user)
      render strip, status: :gone, layout: false
    end

    # The card of a top-level block as `pages/show.html.erb` draws it.
    def card_for(block, outline:, editable:, first:, last:)
      common = { page: @record, locale: admin_locale, url_options: admin_url_options, first:, last:, editable:, holds: }
      if Admin::EditorScreen::SectionCardComponent.draws?(block, outline:)
        Admin::EditorScreen::SectionCardComponent.for(section: block, outline:, **common)
      else
        Admin::EditorScreen::BlockCardComponent.new(block:, **common)
      end
    end

    # The elements that are this block: its card; or, in a section on the
    # default tab, its tile and its panel (on a translation tab a block in a
    # section is a card of its section's group).
    def parts_of(block, outline:, editable:, change:)
      common = { page: @record, block:, locale: admin_locale, url_options: admin_url_options, editable:, holds: }
      if block.section_id.nil?
        top = outline.top_level
        [ Admin::EditorScreen::BlockCardComponent.new(**common, first: top.first == block, last: top.last == block, updated_by: change) ]
      elsif admin_locale.to_s == ::Locales.default
        [ Admin::EditorScreen::BlockTileComponent.new(**common),
          Admin::EditorScreen::BlockCardComponent.new(**common, placement: :panel, updated_by: change) ]
      else
        [ Admin::EditorScreen::BlockCardComponent.new(**common, placement: :group, updated_by: change) ]
      end
    end
  end
end
