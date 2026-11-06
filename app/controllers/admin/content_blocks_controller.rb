module Admin
  # Inline block editing in the page editor (cs-studio spec §5.1/§6.1):
  # each block card is its own autosaving form (`update`), plus `create`
  # (the "Add block" row at the end of the list), `destroy`, `reorder` (drag
  # or Move up/down) and `duplicate`. Every action is scoped to one page's
  # own blocks (`set_page` + `@page.content_blocks`), never a bare
  # `ContentBlock.find` -- a block has no meaning outside the page it's on,
  # and this is what keeps one editor from PATCHing a block that belongs to
  # a page they don't have open.
  #
  # An action decides: it looks the block up, reads its parameters, claims
  # it, calls the service and asks one responder for its outcome
  # (`Admin::Answers::BlockSaved`, `BlockRefused`, `BlockGone`; the 409s are
  # `Stale` and `Held`, through the concerns). What an answer draws is the
  # responder's, and every action ends in `answer`.
  class ContentBlocksController < BaseController
    include AutosaveResponses
    include PublishingState
    include EditingClaims
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
    # ::MediaColumnComponent`) sends after a pick,
    # or "" after Remove -- `block.definition.uses_columns` still gates
    # which of these a given type's own params are actually read from.
    #
    # `TRANSLATED_COLUMNS` is derived from `ContentBlocks::Save::TRANSLATED`
    # rather than a second, hand-kept `%w[caption alt body]` literal -- that
    # service is the one place a translated column actually
    # gets assigned, so this controller's own idea of "which columns are
    # translated" can never drift out of sync with it.
    TRANSLATED_COLUMNS = ContentBlocks::Save::TRANSLATED.map(&:to_s).freeze
    # `uses` column => the param (and attribute) it's sent as.
    ATTRIBUTE_COLUMNS = { "image" => "media_asset_id" }.freeze

    before_action :set_page

    # The "Add block" row (spec §5.1): the new block is appended.
    #
    # The "+" at the end of a section's lane (sections spec §4.2) posts here
    # too, with `section_id` and `column`, read beside `params[:block]`, since
    # they are this controller's own insertion instruction, not a column
    # `ContentBlocks::Save` assigns. The section is looked up among this
    # page's blocks, so another page's is as gone as a deleted one: both are
    # refused before the service is asked (`BlockRefused#unknown_section`).
    # Everything else is the service's and the model's to say
    # (`ContentBlocks::Save`, `ContentBlock#section_rules`): the block lands
    # at the end of that column, and a column the section doesn't have, or a
    # section added into a section, fails the save.
    def create
      section = @page.content_blocks.find_by(id: params[:section_id]) if params[:section_id].present?
      return answer(Admin::Answers::BlockRefused.new(answers_context).unknown_section) if params[:section_id].present? && section.nil?

      attributes = { block_type: params.dig(:block, :block_type) }
      attributes.merge!(section_id: section.id, section_column: params[:column]) if section
      result = ContentBlocks::Save.call(@page.content_blocks.new, attributes: attributes)

      if result.ok?
        answer(Admin::Answers::BlockSaved.new(answers_context).created(result.record, section: section))
      else
        answer(Admin::Answers::BlockRefused.new(answers_context).created(result, section: section))
      end
    end

    # The block card's own autosave endpoint (spec §6.1), the same shape as
    # `Admin::PagesController#update`: PATCHes on every field's `input`
    # (debounced) or `focusout`, answered with the shared Turbo Stream
    # response whether it saved or not. A block that no longer exists is a 410
    # (`Admin::Answers::BlockGone`) rather than a `RecordNotFound`.
    #
    # A section's settings (sections spec §4.1) are saved here too, from the
    # form in its card (`Admin::EditorScreen::SectionCardComponent`): the same
    # ids, the same stale-save refusal, the same error slots, one per setting,
    # since a section's settings are its schema's fields.
    def update
      block = @page.content_blocks.find_by(id: params[:id])
      return answer(Admin::Answers::BlockGone.new(answers_context).answer) unless block

      # The block's own base (its `updated_at`), not the page's: the page
      # settings form has a base of its own (`Page#settings_changed_at`), which
      # a block write never moves (`AutosaveResponses#refuse_stale_autosave`).
      # A save is a claim (`Admin::EditingClaims`): the tab holds the block or is
      # refused, before the stale check; a stale refusal gives back a claim
      # this very request just took.
      claim = claim_before_save(block, record: @page, status_id: Admin::EditorScreen::BlockCardComponent.status_id(block),
        error_prefix: Admin::EditorScreen::BlockCardComponent.error_prefix(block), reload_url: admin_page_path(@page, **admin_url_options))
      return if performed?

      attributes, translations = split_block_params(block)
      stored_asset_id = block.media_asset_id
      layout_before = Admin::Answers::BlockDrawing.stored_layout(block)
      columns_before = block.column_count
      result = saving_under(claim, block, record: @page) { ContentBlocks::Save.call(block, attributes: attributes, translations: { admin_locale => translations }) }

      autosave = autosave_stream(
        record: result.record,
        result: result,
        status_id: Admin::EditorScreen::BlockCardComponent.error_prefix(block) + "-save-status",
        error_prefix: Admin::EditorScreen::BlockCardComponent.error_prefix(block),
        fields: without_untouched_media_slot(block_error_fields(block), "image", sent: attributes[:media_asset_id], stored_before: stored_asset_id)
      )

      # A refused image choice puts the field back to the stored image (and
      # shows why) -- see `Admin::MediaFields`.
      refused_media = refused_media_field_stream(result, attribute: :media_asset_id, error_attribute: :image,
        sent: attributes[:media_asset_id]) do |stored, errors|
        Admin::EditorScreen::BlockCardComponent.image_field(block: block, asset: stored, locale: admin_locale, errors: errors)
      end

      if result.ok?
        answer(Admin::Answers::BlockSaved.new(answers_context).updated(result.record, autosave: autosave, refused_media: refused_media,
          layout_before: layout_before, columns_before: columns_before))
      else
        answer(Admin::Answers::BlockRefused.new(answers_context).updated(result.record, result: result, autosave: autosave, refused_media: refused_media))
      end
    end

    # Permanent (spec §7's "No trash" interim state): the card disappears
    # from the list, with no confirmation round trip beyond the
    # `Ui::ConfirmDialogComponent` the card's own "⋯" menu already gated this
    # request behind. A refusal (no `pages.edit`: a view-only editor never
    # shows the menu, so a stale tab or a forged request) or any other failure
    # leaves the card in place and says why in the page's alert slot, instead
    # of removing a card whose block still exists.
    #
    # A section has two deletes (sections spec §3.3, §4.1), and which one is
    # asked for is said beside the request, in `keep_blocks`, as `section_id`
    # is for an add: with it, the blocks are lifted to the page's own list
    # where the section stood ("Remove section, keep blocks"); without it they
    # go with the section, which the dialog in front of that request has said,
    # with their number. The parameter means nothing for a block that holds
    # none, which is asked of the rows, as the service asks it: a section
    # whose type is gone is no `container?` and is still emptied or lifted
    # (`ContentBlocks::Destroy`).
    #
    # The blocks a kept section held are read before the service runs, to
    # know whose cards to draw afterwards: once lifted, nothing in a row says
    # it was in this section. A block another tab adds to the section between
    # this read and the service's lock is lifted too and gets no card from
    # this answer; it is there on the next load, as it would be for any tab
    # that was not the one adding it.
    def destroy
      block = @page.content_blocks.find_by(id: params[:id])
      return answer(Admin::Answers::BlockGone.new(answers_context).answer) unless block

      section = block.section
      keep_blocks = params[:keep_blocks].present?
      kept_ids = keep_blocks ? block.section_blocks.ids : []
      result = ContentBlocks::Destroy.call(block, keep_blocks: keep_blocks)
      return answer(Admin::Answers::BlockRefused.new(answers_context).refused(result)) unless result.ok?

      answer(Admin::Answers::BlockSaved.new(answers_context).removed(block, kept_ids: kept_ids, section: section))
    end

    # Drag reorder or Move up/down (spec §6.1): the browser already knows the
    # complete new order (a drop event's own DOM order, or a swap before this
    # same request), and `ContentBlocks::Reorder` checks it names exactly this
    # page's blocks and writes it out. A reorder touches no field with its own
    # error slot, so the answer is the list's status line and what the
    # responder draws (`BlockSaved#reordered`, `BlockRefused#reordered`).
    #
    # The order the Undo toast goes back to is read here, before the service
    # runs, and handed over as the Undo's URL; a request with `undo` is that
    # Undo.
    #
    # One container per request (sections spec §3.3): `ids` is the complete
    # new order of the page's own list or, with `section_id` and `column`, of
    # one column of one section; `moved_from[<id>][section_id]` and
    # `[column]` say where each block that comes from another container is
    # expected to be (blank for the top level). They are handed on as they
    # arrived, ids and not attributes: the service casts every value to an
    # integer and looks each up among this page's blocks. A block that is
    # elsewhere, or a column that is gone, is a 422 with the service's
    # message, told from a denial by `result.denied?`.
    #
    # No Undo for a request that names a section or moves a block (a
    # STRUCTURAL one): the toast's Undo is a reorder of the page's own list
    # back to `before`, which can't put a block back into the column it left
    # and would be refused as soon as the list had gained or lost one.
    #
    # Every parameter is read through `one_value` or `moved_from_param`: a
    # forged `section_id[]=1` is an array where an id belongs, and the
    # service casts what it is handed with `to_i`.
    def reorder
      before = Admin::Answers::BlockDrawing.top_level_blocks(@page).ids
      section_id = one_value(params[:section_id])
      origins = moved_from_param
      structural = section_id.present? || origins.any?
      result = ContentBlocks::Reorder.call(@page, ordered_ids_param, section: section_id, column: one_value(params[:column]), moved_from: origins)

      if result.ok?
        answer(Admin::Answers::BlockSaved.new(answers_context).reordered(origins: origins, structural: structural, before: before, undo: params[:undo].present?,
          undo_url: reorder_admin_page_content_blocks_path(@page, ids: before, undo: 1, **admin_url_options)))
      else
        answer(Admin::Answers::BlockRefused.new(answers_context).reordered(result, structural: structural))
      end
    end

    # Duplicate (spec §5.1; sections spec §3.3): `ContentBlocks::Duplicate`
    # makes the copy (of a section, with every block in it) and puts it
    # directly after its source; what is copied is said there. Where the copy
    # is drawn is `BlockSaved#duplicated`'s.
    def duplicate
      source = @page.content_blocks.find_by(id: params[:id])
      return answer(Admin::Answers::BlockGone.new(answers_context).answer) unless source

      result = ContentBlocks::Duplicate.call(source)
      return answer(Admin::Answers::BlockRefused.new(answers_context).refused(result)) unless result.ok?

      answer(Admin::Answers::BlockSaved.new(answers_context).duplicated(result.record, source: source))
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

    # `moved_from` as a plain hash of hashes, or none: a request may leave it
    # out, and a forged one may send anything where the hash belongs, where
    # an entry's does, or where one of its two ids does (`one_value`). An
    # entry that is no hash names no place, which is what the service reads
    # as "the top level" -- and what `move_streams` reads from the same hash.
    def moved_from_param
      moved = params[:moved_from]
      return {} unless moved.respond_to?(:to_unsafe_h)

      moved.to_unsafe_h.transform_values { |from| from.is_a?(Hash) ? from.transform_values { |value| one_value(value) } : {} }
    end

    # The new order as the service takes it: a list of ids. Anything else
    # where the list belongs is no order at all, and an entry that is not one
    # value names no block -- which the service then refuses.
    def ordered_ids_param = (params[:ids].is_a?(Array) ? params[:ids] : []).map { |id| one_value(id) }

    # A parameter that is to be one id or number: an array or a hash in its
    # place (`section_id[]=1`, `column[a]=1`) is read as not sent.
    def one_value(value) = value.is_a?(String) || value.is_a?(Numeric) ? value : nil

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
    # -- there's nothing left to name -- which
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

    def answer(answer) = render(turbo_stream: answer.streams, status: answer.status)

    # What the responders draw with. Built at the first answer, which comes
    # after the action's write: the page's holds are read then, once
    # (`Admin::Answers::Context`).
    def answers_context
      @answers_context ||= Admin::Answers::Context.new(view: view_context, page: @page, locale: admin_locale, url_options: admin_url_options,
        holds: ::Editing::Holds.on(@page, viewer: Current.user, tab: Current.editing_tab), viewer: Current.user)
    end
  end
end
