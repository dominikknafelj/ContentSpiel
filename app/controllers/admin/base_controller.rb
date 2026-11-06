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

    # The rights that open the Trash screen, any one of them (trash spec §6):
    # it lists whatever the viewer could restore or purge, so it opens for
    # anyone holding one of the rights that act on a trashed item. The
    # sidebar's Trash module (`config/initializers/studio_modules.rb`) and
    # `Admin::TrashController#require_trash_access` share the list.
    TRASH_PERMISSIONS = %w[pages.delete posts.delete media.manage media.upload forms.manage trash.empty].freeze

    # The rights that make someone a person who runs the site, for the
    # plain-HTTP notice in the shell (`insecure_notice_viewer?`): the one
    # that changes the site's settings and the one that opens System
    # status, where the same fact is the "HTTPS" check. An editor can do
    # nothing about the connection and is not shown a warning on every
    # screen.
    INSECURE_NOTICE_PERMISSIONS = %w[settings.manage system_status.view].freeze

    FORBIDDEN_MESSAGE = "You don't have permission to open this."

    layout "admin"
    before_action { Current.channel = :admin }
    before_action { Current.editing_tab = request.headers["X-Notes-Tab"].to_s[Live::Signals::TAB] }

    # Every time CS Studio shows or parses -- schedule inputs, "Saved
    # HH:MM", the trash and audit screens, the dashboard -- is in the
    # site's zone (dashboard spec §5). Wrapping the request is what lets
    # the existing `Time.zone.parse`/`strftime` call sites (schedule
    # inputs, `editor_screen/header_component.rb`/`post_form_component.rb`,
    # `occurred_at`/`trashed_at` reads) stay exactly as they are --
    # they've always read/written through `Time.zone`, which was simply
    # always UTC until now.
    around_action :use_site_time_zone

    helper_method :admin_locale, :admin_url_options, :root_page, :pages_landing_path, :admin_modules, :admin_module_badges,
      :trash_badge_count, :notes_badge_count, :insecure_notice_viewer?

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
        # a `fetch` like `admin--translation--translate`'s suggest request takes that
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

    # The modules this actor may see (`StudioModules`), as rows of the shape
    # the sidebar and ⌘K read: `nil` is open to everyone, otherwise any one
    # of the entry's keys will do, and an entry with a `visible` condition
    # only while it holds. Navigation only: each screen gates itself.
    def admin_modules
      @admin_modules ||= StudioModules.entries.select { |entry| (entry.permission.nil? || holds_any?(entry.permission)) && entry.visible? }.map(&:to_row)
    end

    # The counts beside the modules this actor sees, by module name, for the
    # sidebar: one per module with a badge, and none for a module they don't
    # see, which costs no query.
    def admin_module_badges
      admin_modules.select { |row| StudioModules.badged?(row[:name]) }.to_h { |row| [ row[:name], admin_module_badge(row[:name]) ] }
    end

    # One module's count for this request's actor, asked once per request:
    # a view that shows the same number (the dashboard's card, the inbox's
    # "Mark all read") costs nothing more. 0 where the actor doesn't see the
    # module.
    def admin_module_badge(name)
      @admin_module_badges ||= {}
      @admin_module_badges.fetch(name) do
        @admin_module_badges[name] = admin_modules.any? { |row| row[:name] == name } ? StudioModules.count(name, viewer: Current.actor) : 0
      end
    end

    # A count the action has read already (the Trash screen's tab counts),
    # so the sidebar does not ask it again.
    def known_admin_module_badge(name, count) = (@admin_module_badges ||= {})[name] = count

    # The Dashboard's count: the viewer's unread notes (notes spec §5).
    def notes_badge_count = admin_module_badge(:dashboard)

    # The Trash's count: how many trashed items this viewer could act on.
    def trash_badge_count = admin_module_badge(:trash)

    def holds_any?(keys) = Array(keys).any? { |key| can?(key) }

    # Who the shell tells that CS Studio was reached over plain HTTP
    # (`Admin::Ui::InsecureNoticeComponent`, in the layout): whoever runs
    # the site. Navigation, not a gate: it decides what is drawn, and
    # nothing is refused by it.
    def insecure_notice_viewer? = holds_any?(INSECURE_NOTICE_PERMISSIONS)

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
