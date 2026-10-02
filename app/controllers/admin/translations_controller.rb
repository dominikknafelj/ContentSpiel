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
  # Where a record stands is `Translations::Status`, which is computed per
  # record in Ruby (field digests, block roll-ups, schema fields) -- there
  # is no column to `WHERE` on. So the list is built by walking every
  # readable record in id-ordered batches, computing each batch's states in
  # one go (one blocks query per batch), and keeping the ones that aren't
  # complete -- lazily, stopping as soon as this page (plus the one extra
  # row that tells whether there's a next page, the Media module's
  # `limit(N+1)` shape) is filled. The first pages are therefore cheap; a
  # late page, or a language with few gaps, walks the whole content once
  # per request. That's acceptable at CMS scale (hundreds to a few
  # thousand records) and tracked in the roadmap: a stored per-locale
  # state, kept current by the save services, is the way out if it isn't.
  class TranslationsController < BaseController
    include TranslatableRecordLoading

    PER_PAGE = 50
    BATCH_SIZE = 200

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
      @offset = offset

      items = needing_work.drop(@offset).first(PER_PAGE + 1)
      @has_next = items.size > PER_PAGE
      @items = items.first(PER_PAGE)
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
      render turbo_stream: suggestion_streams(fields, translation, result), status: status
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

    def suggestion_streams(fields, translation, result)
      requested_inputs(fields).map do |field, input_id|
        box = Admin::TranslationScreen::SuggestionComponent
        component =
          if !result.ok? then box.new(input_id: input_id, locale: params[:locale], error: result.errors.to_sentence)
          elsif translation.suggestions.key?(field)
            box.new(input_id: input_id, locale: params[:locale], suggestion: translation.suggestions[field], warnings: translation.warnings[field])
          else box.new(input_id: input_id, locale: params[:locale], error: NOTHING_TO_TRANSLATE)
          end
        turbo_stream.update(box.dom_id(input_id), component)
      end
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

    # A lazy enumerator of `Item`s, types in `TYPES` order, each by id.
    def needing_work
      types = @type ? [ @type ] : @types
      types.lazy.flat_map do |type|
        readable(type).find_in_batches(batch_size: BATCH_SIZE).lazy.flat_map do |batch|
          Translations::Status.for(batch, locales: [ @locale ]).filter_map do |record, states|
            state = states.fetch(@locale)
            Item.new(type:, record:, state:) unless state == :complete
          end
        end
      end
    end

    def readable(type)
      case type
      when "page" then admin_scope(Page.all)
      when "post" then admin_scope(Post.all)
      when "media" then Media::Asset.kept
      end
    end

    def offset
      raw = params[:offset].to_i
      raw.positive? ? raw : 0
    end
  end
end
