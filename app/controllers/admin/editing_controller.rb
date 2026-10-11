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
        Admin::EditorScreen::PageSettingsFormComponent.new(page: @record, locale: admin_locale, url_options: admin_url_options)
      else
        Admin::EditorScreen::PostFormComponent.new(post: @record, locale: admin_locale, url_options: admin_url_options, slot_context: {}, form_only: true)
      end
      render form, layout: false
    end

    private

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
    # block this page's audit log says was deleted is a 410. Asked of the
    # event `ContentBlocks::Destroy` writes, which names its page.
    def block_gone
      deleted = Audit::Event.where(action: "block.deleted", subject_type: "ContentBlock", subject_id: params[:block_id].to_i)
        .order(id: :desc).first
      raise ActiveRecord::RecordNotFound unless deleted && deleted.metadata.to_h["page_id"] == @record.id

      head :gone
    end

    # The card of a top-level block as `pages/show.html.erb` draws it.
    def card_for(block, outline:, editable:, first:, last:)
      common = { page: @record, locale: admin_locale, url_options: admin_url_options, first:, last:, editable: }
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
      common = { page: @record, block:, locale: admin_locale, url_options: admin_url_options, editable: }
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
