module Admin
  # The Pages module (cs-studio spec §4.1/§5.1) and CS Studio's home:
  # the tree, creating a page from just a title, and the page editor
  # itself -- its record header (publish state, delete) and its
  # autosaving "Page settings" form.
  #
  # `AutosaveResponses` is shared with every later editor this task's brief
  # calls out (a block card, the post form) -- only `update` here uses it;
  # `publish`/`unpublish`/`schedule` are deliberately plain POSTs with a
  # redirect + flash rather than another autosave endpoint, since publishing
  # is a one-shot, deliberate action (spec §5.1's own "Publish now /
  # Unpublish / Schedule…, Delete" list), not something that should fire the
  # moment a field loses focus.
  class PagesController < BaseController
    include AutosaveResponses

    # Which of `params[:page]`'s keys are translated columns (`Pages::Save`'s
    # own `TRANSLATED`, kept in sync by hand rather than referencing that
    # constant directly -- this list is *this controller's* contract with
    # the settings form, not `Pages::Save`'s; the two only happen to agree
    # today) versus plain attributes. Split here, not left to `Pages::Save`,
    # because `attributes:` there is assigned with no allowlist of its own
    # (`page_type`/`hero_image` are the only two attributes an editor's own
    # PATCH may ever set -- anything else, e.g. `published`/`parent_id`,
    # must never arrive by way of a form field with that name).
    TRANSLATED_FIELDS = %w[title slug subtitle meta_title meta_description hero_alt].freeze
    ATTRIBUTE_FIELDS = %w[page_type hero_image].freeze

    before_action :set_page, only: %i[show update destroy publish unpublish schedule]

    def index
      @page = nil
    end

    # "+" in the tree, or the module's own "Add a page" (spec §5.1) -- both
    # land here with an optional `parent_id`, asking for nothing but a
    # title. A page with no parent given yet (no page selected in the tree)
    # falls back to the homepage in `create` below, not here: leaving
    # `@page.parent_id` nil is what tells the hidden field (and, if the
    # title turns out blank, the re-rendered form) to show no parent chosen
    # rather than silently pre-filling the homepage's id.
    def new
      @page = Page.new(parent_id: params[:parent_id])
    end

    # Every field but the title goes through the same defaults regardless of
    # who's asking (spec §5.1): a draft, under whichever parent the tree (or
    # the empty state's own link) named, or the homepage if none did. The
    # slug fills itself from the title (`LocalizedSlug#fill_blank_slugs`,
    # run inside `Pages::Save` -> `Page#save`).
    def create
      result = Pages::Save.call(Page.new, attributes: { parent: requested_parent, published: false },
        translations: { admin_locale => { title: params.dig(:page, :title) } })

      if result.ok?
        redirect_to admin_page_path(result.record, **admin_url_options), status: :see_other
      else
        @page = result.record
        render :new, status: :unprocessable_entity
      end
    end

    # The page editor itself (spec §5.1): the record header (@page carries
    # its own publish state/leaf-ness) plus the autosaving settings form,
    # rendered from the same `@page` a normal GET or a failed `destroy`
    # alike -- there's exactly one "what does this page's editor look like"
    # template, same reasoning as `Admin::TreeComponent` being the one
    # thing "what does the tree look like" can mean.
    def show
    end

    # The settings form's own autosave endpoint (spec §6.1): every field in
    # `params[:page]` PATCHes here together (a plain `<input>`'s `input`
    # event bubbles to the whole form, which is what `FormData` then
    # serializes in full) and answers with the shared Turbo Stream shape
    # (`AutosaveResponses#autosave_stream`) regardless of whether the save
    # succeeded -- Turbo processes a stream response for *any* status code
    # once the request's own `Accept` header asked for one, so a 422 here
    # still lands its per-field errors instead of falling back to a blank
    # error page.
    def update
      page_params = params.fetch(:page, ActionController::Parameters.new).permit(*TRANSLATED_FIELDS, *ATTRIBUTE_FIELDS)
      translated = page_params.slice(*TRANSLATED_FIELDS).to_h
      attributes = page_params.slice(*ATTRIBUTE_FIELDS).to_h

      result = Pages::Save.call(@page, attributes: attributes, translations: { admin_locale => translated })

      render turbo_stream: autosave_stream(
        record: result.record,
        result: result,
        status_id: "page-save-status",
        error_prefix: "page",
        base_updated_at: params[:base_updated_at],
        fields: page_error_fields
      ), status: (result.ok? ? :ok : :unprocessable_entity)
    end

    # Deleting is permanent (spec §7's own "No trash" interim state) and
    # refused outright for a branch that still has children
    # (`Page#ensure_no_children`, run by `Pages::Destroy`) -- the header's
    # own Delete button is already disabled with that reason before a
    # request is ever sent, but a direct request (or a stale page whose
    # children changed in another tab) still has to get the same answer
    # from the server, not just the client.
    def destroy
      result = Pages::Destroy.call(@page)

      if result.ok?
        redirect_to admin_root_path(**admin_url_options), status: :see_other
      else
        @page = result.record
        flash.now[:alert] = result.errors.to_sentence
        render :show, status: :unprocessable_entity
      end
    end

    # Publish now (spec §5.1): live immediately, keeping a live page's own
    # `published_at` untouched (`Pages::Save#assign_publishing`) -- this is
    # "make it live right now" even for a page that was already scheduled
    # ahead, not "clear the schedule".
    def publish
      redirect_after Pages::Save.call(@page, attributes: { published: true }), success: "Published"
    end

    def unpublish
      redirect_after Pages::Save.call(@page, attributes: { published: false }), success: "Unpublished"
    end

    # Schedule… (spec §5.1): a future `published_at` wins outright over the
    # `published:` true/false shorthand (`Pages::Save#assign_publishing`),
    # so this is the one action here that can also *un*-schedule a page
    # back to a later date without first unpublishing it.
    def schedule
      at = Time.zone.parse(params[:published_at].to_s)

      if at.nil?
        redirect_to admin_page_path(@page, **admin_url_options), status: :see_other, alert: "Choose a date and time"
        return
      end

      redirect_after Pages::Save.call(@page, attributes: { published_at: at }), success: "Scheduled"
    rescue ArgumentError
      redirect_to admin_page_path(@page, **admin_url_options), status: :see_other, alert: "Choose a date and time"
    end

    private

    def set_page
      @page = Page.find(params[:id])
    end

    # `slug`'s error key isn't `:slug` -- `LocalizedSlug` reports it against
    # the locale-suffixed accessor (`slug_en`, `slug_de`, ...) for whichever
    # locale actually failed, since a slug has no fallback the way a blank
    # title does (see that concern's own comment). Only the accessor for
    # *this* editing locale is checked here, matching the one slug input the
    # settings form actually shows -- a collision reported against some
    # other locale's slug would otherwise surface on a field the editor
    # currently viewing this form can't even see.
    def page_error_fields
      {
        title: [ :title ],
        slug: [ Mobility.normalize_locale_accessor(:slug, admin_locale) ],
        subtitle: [ :subtitle ],
        meta_title: [ :meta_title ],
        meta_description: [ :meta_description ],
        hero_alt: [ :hero_alt ],
        page_type: [ :page_type ],
        hero_image: [ :hero_image ]
      }
    end

    def redirect_after(result, success:)
      if result.ok?
        redirect_to admin_page_path(@page, **admin_url_options), status: :see_other, notice: success
      else
        redirect_to admin_page_path(@page, **admin_url_options), status: :see_other, alert: result.errors.to_sentence
      end
    end

    # `find_by`, not `find`: an absent or stale `parent_id` (the empty
    # state's "Add a page" names none at all) is "use the homepage," not a
    # 404 -- only an *invalid* choice should ever be a hard error, and
    # `Pages::Save` has no rule of its own to catch that distinction since a
    # blank `parent:` there just means "make a new root," which `Page`'s own
    # `only_one_root_page` validation already refuses whenever one exists.
    def requested_parent
      Page.find_by(id: params.dig(:page, :parent_id)) || Page.find_by(parent_id: nil)
    end
  end
end
