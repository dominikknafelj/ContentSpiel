module Admin
  # The Translations matrix (design pass round 2, Task 18, handoff §4.4): one
  # screen for every target language instead of one page per language.
  # Summary cards on top (per language: "% done", a bar, "12 missing · 1
  # outdated"), a type filter, then a matrix whose rows are the items that
  # need work in ANY target language and whose columns are the languages;
  # each cell is that language's state chip linking to the item's editor in
  # that language. `?type=page|post|media|settings` narrows it, `?language=de`
  # (a summary card's link) keeps the rows that need work in that language; `?locale=` is
  # a retired parameter from the one-page-per-language screen and is ignored,
  # so old links (the dashboard card's, bookmarks) still answer 200.
  #
  # `suggest` (the editor's AI Translate buttons, spec §6.4) lives here too,
  # on its own route -- so every filter of the matrix is `only: :index`.
  #
  # What's listed, and counted, is exactly what the actor may read: pages and
  # posts through `AccessControl.scope` (kept records only, so the trash
  # never shows up here), images -- which have no per-record read scope --
  # only for a `media.upload` holder, the same gate the Media module opens
  # on, and only kept ones, and the site settings row (title, tagline) only
  # for `settings.manage`. The summary percentages are over that same set,
  # and a type the actor can't read isn't offered as a filter either.
  #
  # Where a record stands is the stored `translation_states` row
  # (`Translations::StateIndex`, kept current by the save services), so none
  # of this loads records to filter them: the cards come from
  # `StateIndex.summaries` (grouped SQL, two queries per type whatever the
  # number of languages), each type's rows from an EXISTS over the target
  # languages (`exists_in_any_locale_sql`), counted with `COUNT`, and this
  # page is cut out of the types the way the trash list does it: every type
  # contributes its own ordered window of `offset + per_page` rows, they are
  # merged in Ruby by the same sort key and sliced. Cost is proportional to
  # the rows that need work (and to how deep the page is): the ordering
  # expression (`original_changed_at_sql`, a correlated aggregate per row)
  # runs over every row of a type that is missing or outdated in a target
  # language before the window is cut, not just over the page's rows -- and
  # never over the rows that are complete. One `states_for` query supplies
  # every cell. A record with no row reads complete and isn't
  # listed (`StateIndex`).
  #
  # Order (§4.4): rows with an outdated language first -- they are already
  # visible on the site -- the most recently changed first, then rows that
  # only miss something, in the same order of original change. Paging is by page number
  # (`Pagination`, design pass spec §4); the Site settings row isn't paged,
  # it tops the first page.
  class TranslationsController < BaseController
    include TranslatableRecordLoading

    PER_PAGE = 50

    # In display order; `label` heads the filter segment, `short` is the
    # Type column's word.
    TYPES = {
      "page" => { label: "Pages", short: "Page", permission: "pages.read" },
      "post" => { label: "Posts", short: "Post", permission: "posts.read" },
      "media" => { label: "Images", short: "Image", permission: "media.upload" },
      "settings" => { label: "Site settings", short: "Settings", permission: "settings.manage" }
    }.freeze

    # One row of the matrix: `states` is `{ locale => :complete|:missing|:outdated }`
    # for every target language.
    Item = Data.define(:type, :record, :states)

    # What a field gets back when its original is blank -- `AI::Translate`
    # skips it rather than failing the rest of the request.
    NOTHING_TO_TRANSLATE = "The original is empty — nothing to translate".freeze

    # What `suggest` accepts as an input's DOM id: it's echoed back as the
    # target of a stream (`SuggestionComponent.dom_id`), so nothing but a
    # plain id the editors themselves render (`post-title`,
    # `block-12-body-json`, `settings_fields-text`).
    INPUT_ID = /\A[A-Za-z][\w-]*\z/

    before_action :require_read_access, only: :index
    before_action :require_target_languages, only: :index

    def index
      @target_locales = Translations.target_locales
      readable = readable_relations
      @types = TYPES.keys.select { |type| readable.key?(type) || (type == "settings" && can?("settings.manage")) }
      @type = params[:type].presence_in(@types)
      # `?language=de` (a summary card's link, the dashboard's): only the rows
      # that need work in that language. All the columns stay.
      @language = params[:language].presence_in(@target_locales)
      @needed_in = @language ? [ @language ] : @target_locales

      @summaries = Translations::StateIndex.summaries(@target_locales, readable.values)
      # What each type would list: the filter's counts, grouped SQL over the
      # index. "Site settings" is one row or none.
      @counts = readable.transform_values { |relation| relation.where(needs_work(relation.klass)).count }
      settings = settings_item
      @counts["settings"] = settings ? 1 : 0 if @types.include?("settings")
      # The settings row is on top of the page's 50, not one of them: page 1
      # renders 51 rows with it, the pagination total (and so the page count)
      # leaves it out because it is never paged, while the toolbar's "All" and
      # "Site settings" counts include it, being what those filters show.

      shown = (@type ? [ @type ] : readable.keys).select { |type| readable.key?(type) }
      @pagination = Pagination.new(page: params[:page], per_page: PER_PAGE, total: shown.sum { |type| @counts.fetch(type) })
      @items = @pagination.out_of_range? ? [] : items_on_page(readable.slice(*shown))
      @items.unshift(settings) if settings && [ nil, "settings" ].include?(@type) && @pagination.page == 1
    end

    # AI suggestions for some of one record's fields (translation helpers
    # spec §6.4), asked by the editor's Translate buttons and its
    # "Suggest translations for N empty fields" (one request per record and cap-sized part,
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

    # With a single language enabled there's nothing to translate into (the
    # sidebar hides the entry then), so the dashboard.
    def require_target_languages
      redirect_to admin_root_path, status: :see_other if Translations.target_locales.empty?
    end

    # `{ type => relation }` of the read-scoped, kept records, in `TYPES`
    # order, only for the types the actor may read.
    def readable_relations
      relations = {}
      relations["page"] = admin_scope(Page.all) if can?("pages.read")
      relations["post"] = admin_scope(Post.all) if can?("posts.read")
      relations["media"] = Media::Asset.kept if can?("media.upload")
      relations
    end

    def needs_work(model)
      Translations::StateIndex.exists_in_any_locale_sql(model, states: %w[missing outdated], locales: @needed_in)
    end

    # The settings row, when the actor may manage settings and the title or
    # tagline isn't complete in every target language.
    def settings_item
      return unless can?("settings.manage")

      site = Current.site
      states = Translations::StateIndex.states_for([ site ], locales: @target_locales).fetch(site)
      Item.new(type: "settings", record: site, states:) if @needed_in.any? { |locale| states[locale] != :complete }
    end

    # This page's `Item`s. Each type's relation is ordered (`StateIndex
    # .work_list`) outdated-first then by when its ORIGINAL last changed,
    # newest first (`StateIndex.original_changed_at_sql`: the stored per-field stamps, blocks rolled in,
    # never `updated_at`, which any save -- a translation-only one included --
    # moves), and cut to `offset + per_page` rows; the windows are
    # merged by the same key (ties: type order, then newest id) and sliced.
    def items_on_page(relations)
      window = @pagination.offset + PER_PAGE
      type_order = relations.keys
      candidates = relations.flat_map do |type, relation|
        Translations::StateIndex.work_list(relation, locales: @needed_in).limit(window).map { |record| [ type, record ] }
      end
      page = candidates.sort_by { |type, record| [ record[:has_outdated] ? 0 : 1, -record[:original_changed_at].to_r, type_order.index(type), -record.id ] }
        .slice(@pagination.offset, PER_PAGE) || []
      states = Translations::StateIndex.states_for(page.map(&:last), locales: @target_locales)
      page.map { |type, record| Item.new(type:, record:, states: states.fetch(record)) }
    end
  end
end
