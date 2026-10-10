module Admin
  # Everything in CS Studio (cs-studio spec §4.1): signed-in only (inherited
  # Authentication), the admin layout, the :admin channel for services, and the
  # editing locale every screen reads.
  #
  # Access control (design spec §3.4 "Controllers"), three tools every
  # module controller uses:
  # - `require_permission(key)` for an admin *area* (Users, Settings, ...):
  #   without the key anywhere, the 403 page (`forbidden!`);
  # - `admin_scope(relation)` for *records*: loading through the actor's
  #   read scope, so an id outside it raises `RecordNotFound` -- a 404,
  #   never a 403, so a record's existence isn't disclosed (§3.3 "Not
  #   found, not forbidden", Review Focus 2);
  # - `can?`/`can_edit?` (`AccessControlHelper`) for what to show.
  # The services decide every write again; a denial they return is answered
  # with `forbidden!` (HTML/JSON) or a 403 Turbo Stream by each controller.
  class BaseController < ApplicationController
    include AccessControlHelper
    # Helpers for this controller's own use, not actions.
    private(*AccessControlHelper.public_instance_methods)

    # The modules column (cs-studio spec §4.2), in order: each entry is
    # shown only when the actor holds its `permission` anywhere (`can?`
    # without a record); `nil` is open to every signed-in user (the
    # dashboard, CS Studio's home, dashboard spec §3-§4 -- and the AI
    # assistant screen, which lists and manages the user's own tokens,
    # spec §5). One list for the sidebar (`admin_modules`) and for where
    # the Pages index sends someone who can't read pages
    # (`first_admin_module_path`), so the two can never disagree about
    # what a user can open -- with Dashboard listed first and always open,
    # that fallback now always lands on the dashboard.
    #
    # A `permission` Array means *any* of them (trash spec §6): the Trash
    # screen lists whatever the viewer could restore or purge, so it opens
    # for anyone holding one of the rights that act on a trashed item --
    # `Admin::TrashController#require_trash_access` gates on the very same
    # list (`TRASH_PERMISSIONS`).
    TRASH_PERMISSIONS = %w[pages.delete posts.delete media.manage media.upload trash.empty].freeze

    # An entry's optional `if:` is a further condition, a lambda evaluated
    # per request (`admin_modules`) for what a static `permission` can't
    # say -- the Translations overview (translation helpers spec §4) only
    # makes sense with more than one language enabled, which is a runtime
    # site setting, not a right.
    #
    # `group:` is the sidebar section (design pass spec §4, handoff
    # "StudioSidebar"): Content, People, System. The array's order is the
    # sidebar's order within a group, and Dashboard stays first overall --
    # `first_admin_module_path` falls back to `admin_modules.first`, which
    # must keep landing on an always-open module.
    MODULE_GROUPS = { content: "Content", people: "People", system: "System" }.freeze

    MODULES = [
      { label: "Dashboard", icon: :dashboard, path: :admin_root_path, permission: nil, group: :content },
      { label: "Pages", icon: :pages, path: :admin_pages_path, permission: "pages.read", group: :content },
      { label: "Posts", icon: :posts, path: :admin_posts_path, permission: "posts.read", group: :content },
      { label: "Media", icon: :media, path: :admin_media_path, permission: "media.upload", group: :content },
      { label: "Translations", icon: :translations, path: :admin_translations_path, permission: %w[pages.read posts.read],
        if: -> { Locales.enabled.size > 1 }, group: :content },
      { label: "Tags", icon: :tags, path: :admin_tags_path, permission: "tags.manage", group: :content },
      { label: "Mind graph", icon: :graph, path: :admin_mind_graph_path, permission: "posts.read", group: :content },
      { label: "Trash", icon: :trash, path: :admin_trash_path, permission: TRASH_PERMISSIONS, group: :content },
      { label: "Users", icon: :users, path: :admin_users_path, permission: "users.manage", group: :people },
      { label: "Groups", icon: :groups, path: :admin_groups_path, permission: "groups.manage", group: :people },
      { label: "Settings", icon: :settings, path: :admin_settings_path, permission: %w[settings.manage languages.manage], group: :system },
      { label: "AI assistant", icon: :assistant, path: :admin_api_tokens_path, permission: nil, group: :system },
      { label: "System status", icon: :status, path: :admin_system_status_path, permission: "system_status.view", group: :system },
      { label: "Audit log", icon: :audit, path: :admin_audit_events_path, permission: "audit.view", group: :system }
    ].freeze

    FORBIDDEN_MESSAGE = "You don't have permission to open this."

    layout "admin"
    before_action { Current.channel = :admin }

    # Every time CS Studio shows or parses -- schedule inputs, "Saved
    # HH:MM", the trash and audit screens, the dashboard -- is in the
    # site's zone (dashboard spec §5). Wrapping the request is what lets
    # the existing `Time.zone.parse`/`strftime` call sites (schedule
    # inputs, `editor_screen/header_component.rb`/`post_form_component.rb`,
    # `occurred_at`/`trashed_at` reads) stay exactly as they are --
    # they've always read/written through `Time.zone`, which was simply
    # always UTC until now.
    around_action :use_site_time_zone

    helper_method :admin_locale, :admin_url_options, :root_page, :pages_landing_path, :admin_modules, :trash_badge_count, :notes_badge_count

    # A record outside the viewer's scope and a record that doesn't exist
    # answer identically (access-control design spec §3.3) -- now inside the
    # Studio layout rather than the app's bare 404, so the way on (the
    # sidebar) is still there. Signed-in requests only: authentication runs
    # first, so a signed-out visitor is redirected to sign-in before any
    # lookup can raise. Only an HTML request gets the page: an autosave's
    # Turbo Stream or a JSON upload would take it for a body to render or
    # parse, so those get a bare 404 (`head`), as before. A Turbo Frame
    # request is HTML and gets the page too -- the layout supplies the
    # `<turbo-frame id="content">` it expects.
    rescue_from ActiveRecord::RecordNotFound do
      # `symbol == :html`, not `format.html?`: Mime::Type#html? is true for
      # any type whose string contains "html", Turbo Stream's
      # "text/vnd.turbo-stream.html" included.
      if request.format.symbol == :html
        render "admin/errors/not_found", status: :not_found
      else
        # `head` would label the empty body with the *request's* format --
        # for a Turbo Stream request, "text/vnd.turbo-stream.html" -- and
        # a `fetch` like `admin--translate`'s suggest request takes that
        # content type to mean "a stream, render it" (an empty one) rather
        # than "not a stream, show the generic error". An explicit
        # text/plain keeps a bare 404 reading as what it is.
        head :not_found, content_type: "text/plain"
      end
    end

    private

    def use_site_time_zone(&block)
      Time.use_zone(Current.site.effective_time_zone, &block)
    end

    # The `MODULES` entries this actor may open: `nil` is open to everyone,
    # otherwise any one of the entry's keys will do -- and an entry with an
    # `if:` lambda only while it's true.
    def admin_modules
      @admin_modules ||= MODULES.select do |entry|
        (entry[:permission].nil? || holds_any?(entry[:permission])) && (entry[:if].nil? || entry[:if].call)
      end
    end

    # The sidebar's Trash badge (design pass spec §4): how many trashed
    # items *this viewer* could act on -- the same delete-right scopes the
    # Trash screen lists with (page branch roots, posts, images;
    # `Admin::TrashController.badge_count`), so the number matches what
    # they'd see there. Three COUNTs per CS Studio page load, each on the
    # indexed `trashed_at`; none at all when the viewer can't open Trash.
    def trash_badge_count
      return 0 unless admin_modules.any? { |entry| entry[:path] == :admin_trash_path }

      # (`Admin::TrashController#index` presets it from its tabs' counts.)
      @trash_badge_count ||= Admin::TrashController.badge_count(Current.actor)
    end

    # The Dashboard entry's count in the sidebar: the viewer's unread notes
    # (notes spec §5), on records they may read now. The sidebar is on every
    # CS Studio page, so this is paid on every page load: exactly one COUNT on
    # `note_deliveries`, narrowed by the read scope as a subquery and served
    # by the `(user_id, read_at)` index; none for an answer that renders no
    # layout. Memoized, so a view that asks too (the dashboard's card, the
    # inbox's "Mark all read") costs nothing more.
    def notes_badge_count
      @notes_badge_count ||= Current.user ? Dashboard::NotesForYou.new(actor: Current.actor).unread_count : 0
    end

    def holds_any?(keys) = Array(keys).any? { |key| can?(key) }

    def first_admin_module_path
      entry = admin_modules.first
      entry && send(entry[:path], **admin_url_options)
    end

    # For an area controller's `before_action`: the 403 page unless the
    # actor holds `key` anywhere. Rendering halts the action chain.
    def require_permission(key)
      forbidden! unless can?(key)
    end

    # `relation` narrowed to what the actor may `key` (by default the
    # model's own `read`: `Post` -> `posts.read`, `Page` -> `pages.read`),
    # so a `find` on it 404s for a record out of scope. Reads only --
    # whether the actor may *change* a loaded record is its service's call.
    def admin_scope(relation, key = "#{relation.model.table_name}.read")
      AccessControl.scope(Current.actor, key, relation)
    end

    # The 403 answer (design spec §5 "The 403 page matches the product
    # layout"): JSON `{errors:}` for a JSON request (the editor's upload
    # endpoint), otherwise the forbidden page inside the admin layout --
    # also for a Turbo form submission, which renders an error response's
    # HTML in place. `message` is a service's refusal ("You don't have
    # permission to publish posts") when there is one.
    #
    # An autosave (a Turbo Stream request from `admin--saving--autosave`) refused
    # here -- a tab left open after the user lost the area -- gets the
    # 403 save-status stream a service refusal gets
    # (`AutosaveResponses#autosave_status`), in the status line the
    # controller names (`forbidden_status_id`), rather than an HTML page
    # the autosave controller would take for a network failure and retry.
    def forbidden!(message = nil)
      message ||= FORBIDDEN_MESSAGE
      status_id = request.format.turbo_stream? ? forbidden_status_id : nil

      if request.format.json?
        render json: { errors: [ message ] }, status: :forbidden
      elsif status_id
        render turbo_stream: turbo_stream.replace(status_id, Admin::Ui::SaveStatusComponent.new(id: status_id, state: :forbidden)), status: :forbidden
      else
        render "admin/errors/forbidden", status: :forbidden, formats: [ :html ], content_type: "text/html", locals: { message: message }
      end
    end

    # The save-status line of this request's autosave form, for
    # `forbidden!`; nil where the action isn't an autosave.
    def forbidden_status_id = nil

    # A service failure answered in HTML: the 403 page for a permission
    # refusal, otherwise whatever the block does for any other failure.
    def forbidden_or(result)
      result.denied? ? forbidden!(result.errors.to_sentence) : yield
    end

    # The homepage (final-fixes round, finding 12) -- one place for what
    # every Pages view and both of its controllers (`PagesController`'s own
    # tree replace/"no parent given" fallback, `TreeController`'s own tree
    # replace) otherwise each re-derived by hand as a bare `Page.find_by
    # (parent_id: nil)`, several times over, with nothing tying them
    # together as "the same lookup" beyond a shared literal -- `Page#
    # only_one_root_page` is what actually guarantees there's ever at most
    # one row this can match. A `helper_method` so every Pages view can call
    # it exactly like a controller action already can, the same way
    # `admin_locale`/`admin_url_options` already are.
    def root_page
      Page.find_by(parent_id: nil)
    end

    # Where "back to the pages" means: Home's editor when the actor can open
    # it (what `/pages` would redirect to anyway -- going there directly
    # saves a hop, which matters for a redirect carrying a flash or an Undo
    # toast), else the Pages index and its "Choose a page from the tree".
    def pages_landing_path
      home = root_page
      if home && admin_scope(Page.where(id: home.id)).exists?
        admin_page_path(home, **admin_url_options)
      else
        admin_pages_path(**admin_url_options)
      end
    end

    # The language being edited: ?locale= when it's enabled, else the site's
    # default. Invalid or disabled codes fall back silently (spec §8).
    def admin_locale
      @admin_locale ||= Locales.enabled?(params[:locale]) ? params[:locale].to_s : Locales.default
    end

    # Link params that keep the editing language across navigation.
    def admin_url_options
      admin_locale == Locales.default ? {} : { locale: admin_locale }
    end
  end
end
