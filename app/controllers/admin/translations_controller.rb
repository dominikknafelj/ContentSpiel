module Admin
  # The Translations overview (translation helpers spec §4): for one target
  # language (`?locale=de`, the editing locale too, so the sidebar and every
  # link keep it), the readable pages, posts and images that are `:missing`
  # or `:outdated` there, grouped by type, each linking to its editor in
  # that language. `?type=page|post|media` narrows it to one type.
  #
  # `suggest` (the editor's AI Translate buttons, spec §6.4) lives here too,
  # on its own route -- so every filter of the overview is `only: :index`.
  #
  # What's listed is exactly what the actor may read: pages and posts
  # through `AccessControl.scope` (kept records only, so the trash never
  # shows up here), images -- which have no per-record read scope -- only
  # for a `media.upload` holder, the same gate the Media module opens on,
  # and only kept ones. A type the actor can't read at all isn't offered
  # as a filter either.
  #
  # Where a record stands is the stored `translation_states` row
  # (`Translations::StateIndex`, kept current by the save services), so the
  # list is a real query: each readable relation is narrowed to `missing`
  # or `outdated` in this language with `StateIndex.joins`, counted with
  # `COUNT`, and this page is cut out of the types in order with
  # `offset`/`limit` -- cost proportional to the page, not the site. A
  # record with no row reads complete and isn't listed (`StateIndex`).
  #
  # Paging is by page number (`Pagination`, design pass spec §4).
  class TranslationsController < BaseController
    include TranslatableRecordLoading

    PER_PAGE = 50

    # In display order; `label` heads the group.
    TYPES = {
      "page" => { label: "Pages", permission: "pages.read" },
      "post" => { label: "Posts", permission: "posts.read" },
      "media" => { label: "Images", permission: "media.upload" }
    }.freeze

    # One row of the list.
    Item = Data.define(:type, :record, :state)

    # What a field gets back when its original is blank -- `AI::Translate`
    # skips it rather than failing the rest of the request.
    NOTHING_TO_TRANSLATE = "The original is empty — nothing to translate".freeze

    # What `suggest` accepts as an input's DOM id: it's echoed back as the
    # target of a stream (`SuggestionComponent.dom_id`), so nothing but a
    # plain id the editors themselves render (`post-title`,
    # `block-12-body-json`, `settings_fields-text`).
    INPUT_ID = /\A[A-Za-z][\w-]*\z/

    before_action :require_read_access, only: :index
    before_action :require_target_locale, only: :index

    def index
      @locale = params[:locale].to_s
      @target_locales = Translations.target_locales
      @types = TYPES.keys.select { |type| can?(TYPES.dig(type, :permission)) }
      @type = params[:type].presence_in(@types)

      relations = needing_work
      sizes = relations.transform_values(&:count)
      @pagination = Pagination.new(page: params[:page], per_page: PER_PAGE, total: sizes.values.sum)
      @items = items_on_page(relations, sizes)
    end

    # AI suggestions for some of one record's fields (translation helpers
    # spec §6.4), asked by the editor's Translate buttons and its
    # "Translate empty fields" (one request per record and cap-sized part,
    # `TranslateAllComponent`). `AI::Translate` decides everything --
    # `ai.translate`, the record's edit right, the caps -- and saves
    # nothing (Review Focus 4); this only loads the record (a 404 outside
    # the actor's read scope, `TranslatableRecordLoading`) and answers with
    # one Turbo Stream per requested field that named its input, updating
    # that field's suggestion box: the suggestion with Use/Discard, or the
    # inline error. The status says how it went (403 for a refusal, 422 for
    # any other failure) but the streams are sent either way, so
    # `admin--translate` always has something to show under the field.
    #
    # `mode=update` is the outdated card's **Suggest update**: the fields
    # already have a translation, and each answer then also shows it
    # ("Current: …", read from the record and never sent to the provider --
    # `SuggestionComponent`) so the editor can compare before pressing Use,
    # which replaces the field's value. Which fields are translated is
    # unchanged: only the requested ones, blank originals still skipped. Any
    # other value of `mode` is the ordinary translate.
    #
    # A request in which no field names a valid input id has nowhere to show
    # anything, so it's a bare 422 before `AI::Translate` runs: no provider
    # call (nothing paid for that nobody could see), no `ai.translated`
    # event. The editor never sends one; `admin--translate` shows its own
    # generic error for a non-stream answer.
    def suggest
      record = load_translatable_record
      fields = requested_fields
      return head(:unprocessable_entity) if requested_inputs(fields).empty?

      translation = AI::Translate.new(record, fields: fields, to: params[:locale].to_s)
      result = translation.call

      status = if result.ok? then :ok
      elsif result.denied? then :forbidden
      else :unprocessable_entity
      end
      render turbo_stream: suggestion_streams(record, fields, translation, result), status: status
    end

    private

    def requested_fields
      fields = params[:fields]
      fields.is_a?(Array) ? fields.grep(String).uniq : []
    end

    # `{ field => input id }` for the requested fields whose `inputs[field]`
    # is a plain DOM id (`INPUT_ID`); a field without one gets no stream --
    # there'd be nowhere to show it.
    def requested_inputs(fields)
      inputs = params[:inputs]
      return {} unless inputs.is_a?(ActionController::Parameters)

      inputs.permit(*fields).to_h.select { |_, input_id| input_id.is_a?(String) && INPUT_ID.match?(input_id) }
    end

    def suggestion_streams(record, fields, translation, result)
      # The model is configuration, shown beside the box's label; nothing about
      # the key is ever read here.
      named = { model: AI.model }
      update = params[:mode].to_s == "update"
      requested_inputs(fields).map do |field, input_id|
        box = Admin::TranslationScreen::SuggestionComponent
        component =
          if !result.ok? then box.new(input_id: input_id, locale: params[:locale], error: result.errors.to_sentence)
          elsif translation.suggestions.key?(field)
            box.new(input_id: input_id, locale: params[:locale], suggestion: translation.suggestions[field], warnings: translation.warnings[field],
              mode: (update ? :update : :translate), current: (current_translation(record, field) if update), **named)
          else box.new(input_id: input_id, locale: params[:locale], error: NOTHING_TO_TRANSLATE)
          end
        turbo_stream.update(box.dom_id(input_id), component)
      end
    end

    # The field's existing translation as plain text (`Translations
    # .source_text`: a string as it is, a rich-text body as its paragraphs,
    # nothing for a value with no sensible text).
    def current_translation(record, field)
      value = Translations.source_text(record.translation_value(field, params[:locale].to_s))
      value.is_a?(Array) ? value.join("\n\n") : value
    end

    # Same keys as the sidebar entry (`MODULES`): either read right opens
    # the screen; the list itself is then narrowed per type.
    def require_read_access
      forbidden! unless holds_any?(%w[pages.read posts.read])
    end

    # Always a real target language in the URL: an unknown, disabled or
    # default code (or none) goes to the first target language, keeping
    # the type filter. With a single language enabled there's nothing to
    # translate into (the sidebar hides the entry then), so the dashboard.
    def require_target_locale
      targets = Translations.target_locales
      return redirect_to(admin_root_path, status: :see_other) if targets.empty?
      return if targets.include?(params[:locale].to_s)

      redirect_to admin_translations_path(locale: targets.first, type: params[:type].presence), status: :see_other
    end

    # `{ type => relation }`, types in `TYPES` order, each narrowed to the
    # readable records that aren't complete in this language.
    def needing_work
      types = @type ? [ @type ] : @types
      types.index_with do |type|
        Translations::StateIndex.joins(readable(type), locale: @locale, states: %w[missing outdated]).order(:id)
      end
    end

    # This page's `Item`s: the relations are laid end to end in type order
    # and `offset`/`limit` cut across them, so a page costs one COUNT per
    # type (`sizes`, shared with the total) plus at most one query per type
    # and one for the states.
    def items_on_page(relations, sizes)
      skip = @pagination.offset
      want = PER_PAGE
      items = []
      relations.each do |type, relation|
        break if want <= 0

        size = sizes.fetch(type)
        if skip >= size
          skip -= size
          next
        end

        records = relation.offset(skip).limit(want).to_a
        states = Translations::StateIndex.states_for(records, locales: [ @locale ])
        items.concat(records.map { |record| Item.new(type:, record:, state: states.dig(record, @locale)) })
        want -= records.size
        skip = 0
      end
      items
    end

    def readable(type)
      case type
      when "page" then admin_scope(Page.all)
      when "post" then admin_scope(Post.all)
      when "media" then Media::Asset.kept
      end
    end
  end
end
