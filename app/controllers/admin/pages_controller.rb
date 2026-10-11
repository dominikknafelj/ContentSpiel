module Admin
  # The Pages module (cs-studio spec §4.1/§5.1), at its own `/pages`
  # (dashboard spec Task 2 -- CS Studio's home is now the dashboard): the
  # tree, creating a page from just a title, and the page editor itself --
  # its record header (publish state, delete) and its autosaving "Page
  # settings" form.
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
    include EditingClaims
    include Scheduling
    include MediaFields

    # Which of `params[:page]`'s keys are translated columns (`Pages::Save`'s
    # own `TRANSLATED`, kept in sync by hand rather than referencing that
    # constant directly -- this list is *this controller's* contract with
    # the settings form, not `Pages::Save`'s; the two only happen to agree
    # today) versus plain attributes. Split here, not left to `Pages::Save`,
    # because `attributes:` there is assigned with no allowlist of its own
    # (`page_type`/`hero_media_asset_id` are the only two attributes an
    # editor's own PATCH may ever set -- anything else, e.g.
    # `published`/`parent_id`, must never arrive by way of a form field with
    # that name). `hero_media_asset_id` is the hero field's hidden input
    # (`Admin::Columns::MediaColumnComponent`, media library Task 8): an id
    # chosen in the picker, or "" to clear it -- `Pages::Save`
    # (`Media::Choosing`) checks `media.upload` and that the asset exists
    # for a new one.
    TRANSLATED_FIELDS = %w[title slug subtitle meta_title meta_description hero_alt].freeze
    ATTRIBUTE_FIELDS = %w[page_type hero_media_asset_id].freeze

    before_action :set_page, only: %i[show update destroy publish unpublish schedule]

    # The Pages module's own index (handoff §10 C34): Home's editor when the
    # viewer can open it (303, with the editing language kept), otherwise the
    # empty state "Choose a page from the tree" beside the tree -- a viewer
    # whose grants reach only a deep branch has a tree to choose from but no
    # Home to land on, and must see neither a 404 nor a hint of what Home
    # holds. "Can open" is the read scope, the same rule `set_page` applies
    # to `show`, so this never redirects into a 404. Someone who can't read
    # any page (a group with only tags or settings, say) is sent on to the
    # first module they *can* open rather than shown a 403 -- in practice
    # always the dashboard now (`BaseController::MODULES`'s first entry,
    # open to everyone), same as if they'd signed in fresh.
    #
    # The flash is kept across the redirect: "Starter pages created" is set
    # by `StarterContentsController` for a redirect to this very URL, and
    # would otherwise be spent on this hop.
    def index
      return redirect_to(first_admin_module_path) unless can?("pages.read")

      home = root_page
      if home && admin_scope(Page.where(id: home.id)).exists?
        flash.keep
        return redirect_to(admin_page_path(home, **admin_url_options), status: :see_other)
      end

      @page = nil
    end

    # The no-JS fallback of the New page dialog (design pass round 2, Task
    # 15): the same form (`Admin::EditorScreen::NewPageFormComponent`) as a
    # page of its own. With JavaScript every "+ New page" trigger opens the
    # dialog in the layout instead and never gets here. `parent_id` presets
    # Inside; none means Home (the form's own default).
    #
    # The parent is looked up through the read scope (a parent id outside
    # it is a 404, like any other out-of-scope record), and the form is
    # only offered where the page could actually be created -- `pages
    # .create` on the parent's branch (design spec §3.3 "Create page"),
    # or on the homepage's when none was named, which is where `create`
    # puts it.
    #
    # With no `parent_id` the question is not "may they create under Home"
    # (a branch editor may not, and is still offered the dialog) but "is there
    # anywhere they may create": the form having a choice, as `posts#new` asks
    # of the types. With no page at all it is the right to create the root.
    # A parent that is readable but in the trash (a tree "+" clicked after the
    # page was trashed elsewhere) is no preset rather than a 404 the dialog
    # could never recover from; an unreadable or unknown one stays a 404.
    def new
      parent = requested_new_parent
      @page = Page.new(parent: parent)
      @form = Admin::EditorScreen::NewPageFormComponent.new(url_options: admin_url_options, locale: admin_locale,
        parent_id: parent&.id, title: params[:title])
      allowed = if parent then can?("pages.create", Page.new(parent: parent))
      elsif root_page then @form.choices.any?
      else can?("pages.create", Page.new)
      end
      return forbidden! unless allowed

      # The New page dialog loading its form (`admin--editor--new-record` sets the
      # frame's `src` to this URL): just the frame, no layout. A normal request
      # renders the standalone page.
      render :new_frame, layout: false if turbo_frame_request_id == Admin::EditorScreen::NewPageDialogComponent::FRAME_ID
    end

    # From the New page dialog (title, Inside, Page type) or the standalone
    # form: a draft under the chosen parent -- the homepage if none was named
    # -- with the chosen type. The slug fills itself from the title
    # (`LocalizedSlug#fill_blank_slugs`, run inside `Pages::Save` ->
    # `Page#save`).
    #
    # A refusal that is the editor's to fix (a blank title, a taken or
    # reserved slug, an unknown page type) answers 422: a Turbo Stream that
    # replaces just the dialog's form with the typed values and an error
    # summary, so the dialog stays open and the editor behind it is untouched;
    # a plain request (no JS) gets the standalone page again. A permission
    # refusal is the 403 page, and a parent outside the read scope is a 404
    # (`requested_parent`), as for any forged id.
    def create
      page_type = new_page_params[:page_type].presence
      parent = requested_parent
      return render_new_page_failure(gone: true) if parent == :gone

      # An unknown `page_type` is `Page`'s own validation failure (`enum ...
      # validate: true`), reported on the field like any other.
      result = Pages::Save.call(Page.new, attributes: { parent: parent, published: false, page_type: page_type }.compact,
        translations: { admin_locale => { title: new_page_params[:title] } })

      if result.ok?
        redirect_to admin_page_path(result.record, **admin_url_options), status: :see_other
      else
        forbidden_or(result) do
          @page = result.record
          @page.errors.add(:base, result.errors.to_sentence) if @page.errors.empty?
          render_new_page_failure
        end
      end
    end

    # The page editor itself (spec §5.1): the record header (@page carries
    # its own publish state/leaf-ness) plus the autosaving settings form,
    # rendered from the same `@page` a normal GET or a failed `destroy`
    # alike -- there's exactly one "what does this page's editor look like"
    # template, same reasoning as `Admin::PagesScreen::TreeComponent` being the one
    # thing "what does the tree look like" can mean.
    #
    # The editor asks `can?` about this one page many times (header
    # buttons, settings, every block card); its branch is loaded once, up
    # front (final fix wave, Minor 10), so no check pays for a closure
    # query. Only here: a write action hands `@page` to a service, which
    # must judge the page's position as stored, not a snapshot
    # (`AccessControl.preload_branches`).
    #
    # The hero and every image block's image are preloaded with their
    # variant records (`Media::Asset::VARIANT_INCLUDES`): each image field
    # reads `#srcset` for its thumbnail, which would otherwise be a query
    # per block (media library Task 8: every list of assets loads that way).
    def show
      AccessControl.preload_branches([ @page ])
      ActiveRecord::Associations::Preloader.new(records: [ @page ], associations: [
        { hero_media_asset: Media::Asset::VARIANT_INCLUDES },
        { content_blocks: { media_asset: Media::Asset::VARIANT_INCLUDES } }
      ]).call
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
      # Before anything is read off the form or any service is called -- see
      # `AutosaveResponses#refuse_stale_autosave`.
      # A save is a claim (`Admin::EditingClaims`): first, so a tab that does not
      # hold the settings is refused before the stale check, and a claim this
      # very request just took is given back when the save is refused as stale.
      claim = claim_before_save(@page, record: @page, status_id: "page-save-status", error_prefix: "page", reload_url: admin_page_path(@page, **admin_url_options))
      return if performed?

      page_params = params.fetch(:page, ActionController::Parameters.new).permit(*TRANSLATED_FIELDS, *ATTRIBUTE_FIELDS)
      translated = page_params.slice(*TRANSLATED_FIELDS).to_h
      attributes = page_params.slice(*ATTRIBUTE_FIELDS).to_h

      stored_hero_id = @page.hero_media_asset_id
      result = saving_under(claim, @page, record: @page) { Pages::Save.call(@page, attributes: attributes, translations: { admin_locale => translated }) }

      streams = autosave_stream(
        record: result.record,
        result: result,
        status_id: "page-save-status",
        error_prefix: "page",
        fields: without_untouched_media_slot(page_error_fields, :hero_image, sent: page_params[:hero_media_asset_id], stored_before: stored_hero_id)
      )

      # A refused hero choice puts the field back to the stored hero (and
      # shows why) -- see `Admin::MediaFields`.
      refused = refused_media_field_stream(result, attribute: :hero_media_asset_id, error_attribute: :hero_image,
        sent: page_params[:hero_media_asset_id]) do |stored, errors|
        Admin::EditorScreen::PageSettingsFormComponent.hero_image_field(asset: stored, locale: admin_locale, errors: errors)
      end
      streams << refused if refused

      # The tree column lives outside this form entirely (the layout's own
      # `<aside>`, spec §4.2), so nothing about a normal Turbo Stream
      # response targeting *this* form's own elements would ever touch it
      # on its own (final-fixes round, finding 1) -- left alone, a title
      # edit saved here left the tree showing the page's stale title (and,
      # since `Admin::PagesScreen::TreeNodeComponent#status` reads straight off the same
      # `@page`, would go stale the same way for any other autosaved
      # attribute a later field ever changes what the tree itself renders).
      # Re-rendered on every successful save here, not just when `title`
      # itself was actually in this particular PATCH's own params: the tree
      # render costs a fixed handful of queries however many pages it shows
      # (`Admin::PagesScreen::TreeComponent`'s own comment; pinned by
      # test/components/admin/pages_screen/tree_component_test.rb), its translation
      # markers are one read of the stored `translation_states`, and there's no cheaper way to know
      # from here whether *this* save happened to be the one that mattered
      # to it.
      streams << tree_replace_stream if result.ok?

      render turbo_stream: streams, status: autosave_status(result)
    end

    # Moves the page, with its whole branch, to the trash (`Trash::Move`,
    # trash spec §4.1) -- nothing is deleted from here any more; the
    # permanent delete is `Trash::Purge`, reachable only from the trash.
    # `count` is read before the move (`Trash::Move` itself trashes every
    # kept descendant, so counting after would just see them all already
    # gone): it's both the notice's own "and N subpages" and, unlike a
    # kept-vs-trashed check on `@page.children` alone, the exact number a
    # later Undo (Task 9's `Trash::Restore`) brings back with it. The Undo
    # link's own URL carries `from: "undo"` (`Admin::TrashController#restore`)
    # so restoring lands the actor back on this page's editor, not the
    # Trash screen.
    def destroy
      count = @page.descendants.kept.count
      result = Trash::Move.call(@page)

      if result.ok?
        notice = count.zero? ? "Moved “#{@page.title}” to the trash" : "Moved “#{@page.title}” and #{helpers.pluralize(count, "subpage")} to the trash"
        flash[:undo] = { "label" => "Undo", "url" => admin_restore_trash_item_path("page", @page, from: "undo", **admin_url_options) }
        redirect_to pages_landing_path, notice:, status: :see_other
      else
        forbidden_or(result) do
          @page = result.record
          flash.now[:alert] = result.errors.to_sentence
          render :show, status: :unprocessable_entity
        end
      end
    end

    # Publish now (spec §5.1): live immediately, keeping a live page's own
    # `published_at` untouched (`Pages::Save#assign_publishing`) -- this is
    # "make it live right now" even for a page that was already scheduled
    # ahead, not "clear the schedule".
    def publish
      return if refuse_instant_redirect(@page, to: admin_page_path(@page, **admin_url_options))

      redirect_after Pages::Save.call(@page, attributes: { published: true }), success: "Published"
    end

    def unpublish
      return if refuse_instant_redirect(@page, to: admin_page_path(@page, **admin_url_options))

      redirect_after Pages::Save.call(@page, attributes: { published: false }), success: "Unpublished"
    end

    # Schedule… (spec §5.1): a future `published_at` wins outright over the
    # `published:` true/false shorthand (`Pages::Save#assign_publishing`),
    # so this is the one action here that can also *un*-schedule a page
    # back to a later date without first unpublishing it.
    def schedule
      editor = admin_page_path(@page, **admin_url_options)
      return if refuse_instant_redirect(@page, to: editor)

      if params[:remove] == "1"
        # "Remove schedule" is only offered for a scheduled record; for any
        # other it must not become an unpublish (a live record's
        # `published_at` is in the past), so it changes nothing.
        return redirect_to editor, status: :see_other unless @page.status == "scheduled"

        return redirect_after Pages::Save.call(@page, attributes: { published_at: nil }), success: "Schedule removed"
      end

      at, error = requested_schedule
      return refuse_schedule(error, editor) if error

      redirect_after Pages::Save.call(@page, attributes: { published_at: at }), success: "Scheduled"
    end

    private

    helper_method :new_page_params

    # Through the read scope (design spec §3.3): a page the actor can't
    # read is a 404 here -- show, autosave, publish and delete alike --
    # never a 403 that would confirm it exists.
    def set_page
      @page = admin_scope(Page.all).find(params[:id])
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

    # See `update`'s own comment for why every successful settings-form
    # save re-renders the tree, not just a title change specifically.
    # `Admin::TreeController#tree_stream`'s own private method builds the
    # identical stream (down to the same `root_page` lookup, `BaseController
    # #root_page`, final-fixes round finding 12) for the drag-to-move
    # endpoint -- not shared as-is, since that one also replaces
    # `tree-status` (the move-specific flash line this controller has no
    # equivalent of), but kept in exact sync with it by hand for the one
    # line the two do share.
    def tree_replace_stream
      turbo_stream.replace("tree", Admin::PagesScreen::TreeComponent.new(root: root_page, selected: @page, locale: admin_locale, url_options: admin_url_options))
    end

    def redirect_after(result, success:)
      if result.ok?
        redirect_to admin_page_path(@page, **admin_url_options), status: :see_other, notice: success
      else
        forbidden_or(result) { redirect_to admin_page_path(@page, **admin_url_options), status: :see_other, alert: result.errors.to_sentence }
      end
    end

    def requested_new_parent
      parent_id = params[:parent_id]
      return nil if parent_id.blank?

      admin_scope(Page.all).find(parent_id)
    rescue ActiveRecord::RecordNotFound
      raise unless trashed_readable_page?(parent_id)

      nil
    end

    def trashed_readable_page?(id)
      AccessControl.scope(Current.actor, "pages.read", Page.all, trashed: true).exists?(id: id)
    end

    def render_new_page_failure(gone: false)
      @page ||= Page.new
      @page.errors.add(:parent, Admin::EditorScreen::NewPageFormComponent::GONE) if gone
      form = Admin::EditorScreen::NewPageFormComponent.new(
        url_options: admin_url_options, locale: admin_locale, parent_id: (@page.parent_id || new_page_params[:parent_id] unless gone),
        title: new_page_params[:title], page_type: new_page_params[:page_type], errors: @page.errors
      )

      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace(form.form_id, form), status: :unprocessable_entity }
        format.html { render :new, status: :unprocessable_entity }
      end
    end

    # No `parent_id` at all (the empty state's "Add a page" names none) is
    # "use the homepage". A named one is looked up through the read scope
    # like every other record here, the same way `new` does: an id the
    # actor can't read -- or one that no longer exists -- is a 404, never a
    # silent fallback to the homepage that would put the page somewhere
    # the editor didn't choose. `Pages::Save` then decides `pages.create`
    # against the parent's branch.
    #
    # One exception to that 404, for `create` only: a parent the viewer can
    # read that has been moved to the trash since the dialog's form was loaded
    # is not "an id forged outside my scope" -- the editor just lost the race --
    # so it comes back as `:gone`, answered with the form and "Choose a page
    # that still exists." on Inside rather than a bare 404 in an empty dialog.
    # The dialog's three fields, read as scalars only. `params.dig(:page, ...)`
    # raises on `page=x` (a String has no `dig`), and a hash or array where a
    # scalar belongs reached `parameterize` / `find` and 500ed; `permit`
    # drops anything non-scalar, so a forged shape is the ordinary blank-title
    # 422 or the default parent (final review A, M3).
    def new_page_params
      @new_page_params ||= (params[:page].respond_to?(:permit) ? params[:page] : ActionController::Parameters.new).permit(:title, :parent_id, :page_type)
    end

    def requested_parent
      parent_id = new_page_params[:parent_id]
      return root_page if parent_id.blank?

      admin_scope(Page.all).find(parent_id)
    rescue ActiveRecord::RecordNotFound
      raise unless trashed_readable_page?(parent_id)

      :gone
    end
  end
end
