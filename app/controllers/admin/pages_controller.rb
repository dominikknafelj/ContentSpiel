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
    include FileParams

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

    # CS Studio's home. Someone who can't read any page (a group with only
    # tags or settings, say) is sent on to the first module they *can*
    # open rather than shown a 403 the moment they sign in -- there's
    # always one, the AI assistant screen being open to everyone.
    def index
      return redirect_to(first_admin_module_path) unless can?("pages.read")

      @page = nil
    end

    # "+" in the tree, or the module's own "Add a page" (spec §5.1) -- both
    # land here with an optional `parent_id`, asking for nothing but a
    # title. A page with no parent given yet (no page selected in the tree)
    # falls back to the homepage in `create` below, not here: leaving
    # `@page.parent_id` nil is what tells the hidden field (and, if the
    # title turns out blank, the re-rendered form) to show no parent chosen
    # rather than silently pre-filling the homepage's id.
    #
    # The parent is looked up through the read scope (a parent id outside
    # it is a 404, like any other out-of-scope record), and the form is
    # only offered where the page could actually be created -- `pages
    # .create` on the parent's branch (design spec §3.3 "Create page"),
    # or on the homepage's when none was named, which is where `create`
    # puts it.
    def new
      parent = params[:parent_id].present? ? admin_scope(Page.all).find(params[:parent_id]) : nil
      @page = Page.new(parent: parent)
      forbidden! unless can?("pages.create", Page.new(parent: parent || root_page))
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
        forbidden_or(result) do
          @page = result.record
          render :new, status: :unprocessable_entity
        end
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

      # `drop_blank_file_params` (Task 4 fix round 1, see its own doc
      # comment) is what keeps this same PATCH -- resent in full on *every*
      # autosave, whichever field an editor actually touched -- from
      # silently detaching an already-attached hero image the moment a
      # blank `hero_image` file input rides along with it. Removing one on
      # purpose is a separate, explicit signal (`remove_hero_image`, read
      # straight off `params` rather than the permitted/translated split
      # above -- it's a flag this controller consumes itself, never a
      # column `Pages::Save` assigns).
      #
      # A real upload always wins over that flag (fix round 2): the
      # checkbox stays checked in the DOM until this same response
      # re-renders the hero section further down (nothing else in this
      # form's markup gets rebuilt on autosave), so an editor who ticks
      # Remove, then picks a new file *before* that re-render lands, would
      # otherwise resend both in one request -- and without this guard, the
      # stale `remove_hero_image=1` would win and silently drop the very
      # upload they just made. `attributes.key?("hero_image")` here is
      # exactly "a non-blank file survived the drop above", since a blank
      # one never reaches this hash at all.
      attributes = drop_blank_file_params(attributes, fields: %w[hero_image])
      hero_image_changing = attributes.key?("hero_image")
      attributes["hero_image"] = nil if !hero_image_changing && ActiveModel::Type::Boolean.new.cast(params.dig(:page, :remove_hero_image))
      hero_image_changing ||= attributes.key?("hero_image")

      result = Pages::Save.call(@page, attributes: attributes, translations: { admin_locale => translated })

      streams = autosave_stream(
        record: result.record,
        result: result,
        status_id: "page-save-status",
        error_prefix: "page",
        base_updated_at: params[:base_updated_at],
        fields: page_error_fields
      )

      # The hero section (the image preview and the "Remove image"
      # checkbox, `admin/shared/_hero_image_field`) is the one part of this
      # form autosave doesn't otherwise touch on success -- every other
      # field's own value already sits correctly in the input the editor
      # just typed into, but a removed or replaced image has nothing
      # equivalent: the checkbox would stay checked (or the file input
      # would still show the just-picked file) with nothing in the DOM
      # reflecting what actually got saved. Only re-rendered when this
      # save actually touched the attachment, and only on success -- a
      # failed save never reaches `Pages::Save`'s attachment writer at all.
      streams << hero_image_stream(result.record) if result.ok? && hero_image_changing

      # The tree column lives outside this form entirely (the layout's own
      # `<aside>`, spec §4.2), so nothing about a normal Turbo Stream
      # response targeting *this* form's own elements would ever touch it
      # on its own (final-fixes round, finding 1) -- left alone, a title
      # edit saved here left the tree showing the page's stale title (and,
      # since `Admin::TreeNodeComponent#status` reads straight off the same
      # `@page`, would go stale the same way for any other autosaved
      # attribute a later field ever changes what the tree itself renders).
      # Re-rendered on every successful save here, not just when `title`
      # itself was actually in this particular PATCH's own params: the tree
      # render is one query (`Admin::TreeComponent`'s own comment), and
      # there's no cheaper way to know from here whether *this* save
      # happened to be the one that mattered to it.
      streams << tree_replace_stream if result.ok?

      render turbo_stream: streams, status: autosave_status(result)
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

    # The Turbo Stream that brings the hero section's DOM back in sync with
    # what `update` just saved (fix round 2) -- same partial, same ids
    # `Admin::PageSettingsFormComponent` renders on a normal GET, built off
    # `Admin::PageSettingsFormComponent::ID_PREFIX` rather than a second,
    # hand-kept copy of "page", so the two can never drift apart.
    def hero_image_stream(record)
      prefix = Admin::PageSettingsFormComponent::ID_PREFIX

      turbo_stream.replace("#{prefix}-hero-image-section", partial: "admin/shared/hero_image_field", locals: {
        section_id: "#{prefix}-hero-image-section",
        image_id: "#{prefix}-hero_image",
        image_html_name: "#{prefix}[hero_image]",
        image_value: record.hero_image,
        checkbox_id: "#{prefix}-remove_hero_image",
        checkbox_html_name: "#{prefix}[remove_hero_image]",
        show_checkbox: record.hero_image.attached?
      })
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
      turbo_stream.replace("tree", Admin::TreeComponent.new(root: root_page, selected: @page, locale: admin_locale, url_options: admin_url_options))
    end

    def redirect_after(result, success:)
      if result.ok?
        redirect_to admin_page_path(@page, **admin_url_options), status: :see_other, notice: success
      else
        forbidden_or(result) { redirect_to admin_page_path(@page, **admin_url_options), status: :see_other, alert: result.errors.to_sentence }
      end
    end

    # `find_by`, not `find`: an absent or stale `parent_id` (the empty
    # state's "Add a page" names none at all) is "use the homepage," not a
    # 404 -- only an *invalid* choice should ever be a hard error, and
    # `Pages::Save` has no rule of its own to catch that distinction since a
    # blank `parent:` there just means "make a new root," which `Page`'s own
    # `only_one_root_page` validation already refuses whenever one exists.
    #
    # Looked up through the read scope, like every other record here: an
    # unreadable parent id is treated as absent (the homepage), where
    # `Pages::Save` then decides `pages.create` against the homepage's
    # branch instead -- a stale or forged id never reveals whether that
    # page exists.
    def requested_parent
      admin_scope(Page.all).find_by(id: params.dig(:page, :parent_id)) || root_page
    end
  end
end
