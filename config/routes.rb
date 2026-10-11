Rails.application.routes.draw do
  # While setup is required, every route below is unreachable (design spec
  # 2026-09-26 §3): these two catch-alls are declared first, so they win over
  # CS Studio and the public page routes. A lambda, so the constant is only
  # resolved per request (never while routes load during boot).
  constraints(->(request) { Setup::RedirectConstraint.matches?(request) }) do
    match "/", to: redirect("/setup", status: 302), via: :all, as: :setup_required_root
    match "*path", to: redirect("/setup", status: 302), via: :all, format: false, as: :setup_required
  end

  # A component browser for the ViewComponents under app/components
  # (open-types spec §5), development only -- never mounted in test or
  # production, and declared here, before the public catch-alls below, so
  # "/lookbook" isn't swallowed as a page path first. Renders through
  # `ComponentPreviewsController` (config/initializers/view_component.rb),
  # the same controller the preview smoke test
  # (test/components/previews_test.rb) uses, so what an editor sees in
  # Lookbook and what that test asserts never raises are the same rendering
  # path.
  mount Lookbook::Engine, at: "/lookbook" if Rails.env.development?

  # CS Studio, the admin (cs-studio spec §3). Its path is configurable
  # (ContentSpiel::ADMIN_PATH) and sign-in lives under it, so the public site
  # advertises no login page. Declared before /preview and the public
  # catch-alls, which would otherwise swallow it as a page path.
  scope ContentSpiel::ADMIN_PATH, module: :admin, as: :admin do
    get "sign-in", to: "sessions#new", as: :sign_in
    post "sign-in", to: "sessions#create"
    delete "sign-out", to: "sessions#destroy", as: :sign_out

    # ⌘K "Jump to..." results (design pass spec §5.6): a layout-less HTML
    # fragment for the palette's turbo-frame, read-only, open to every
    # signed-in user (each row is already narrowed to what they may read).
    get "jump", to: "jump#show", as: :jump
    resource :password, only: %i[new create]
    get "password/:token/edit", to: "passwords#edit", as: :edit_password
    patch "password/:token", to: "passwords#update", as: :update_password

    # The Pages module (cs-studio spec §4.1/§5.1). `member` adds the three
    # publish-state actions the record header's own buttons post to
    # (Publish now / Unpublish / Schedule…, spec §5.1) -- each its own
    # one-shot POST, deliberately outside the settings form's autosave
    # (`Admin::PagesController`'s own class comment explains why).
    resources :pages, only: %i[index new create show update destroy] do
      member do
        post :publish
        post :unpublish
        post :schedule
      end

      # A page's blocks (cs-studio spec §5.1/§6.1, Task 5): nested under the
      # page rather than a top-level resource, since a block is meaningless
      # without the page it's on and every one of these actions already
      # needs `page_id` to scope its lookup (`Admin::ContentBlocksController
      # #set_page`) -- there is no "show a block on its own" screen for
      # `:show`/`:index` to serve. `reorder` is a `collection` route (it
      # names every block to keep, not one) the same way the page tree's own
      # move endpoint is `resource :tree`, not nested under one page;
      # `duplicate` is a `member` route since it always starts from exactly
      # one existing block.
      resources :content_blocks, only: %i[create update destroy] do
        collection { patch :reorder }
        member { post :duplicate }
      end
    end

    # The page tree's own move endpoint (cs-studio spec §4.2), a `resource`
    # (singular) rather than nested under `pages` -- a move names the page
    # being dragged in its own params (`page_id`), not the URL, since the
    # same one PATCH target serves every node in the tree. `update` only
    # (final-fixes round, finding 11): the tree's own GET is already free on
    # every Pages view via `content_for :tree` -- a bare `:show` here
    # answered a plain GET with a Turbo Stream body, which nothing in this
    # app ever actually requests (no `<turbo-frame src="...">` points at
    # it) and no browser navigating here directly could even render (a
    # `<turbo-stream>` response isn't valid, renderable HTML for a
    # top-level GET).
    resource :tree, only: %i[update], controller: :tree

    # The Tiptap editor's own upload button (design spec §4.1/§4.2): POSTs
    # a multipart `file`, gets back `{ id, url }` (201) or `{ errors }`
    # (422) -- `create` only, kept separate from the Media module's own
    # `media` resource just below: there's no page or post this upload
    # belongs to yet at editing time, so it has no id to nest under, and
    # `Admin::MediaAssetsController#create` is the editor's own, narrower
    # JSON-in-JSON-out contract, not the module's own browse/edit screens.
    resources :media_assets, only: :create

    # The Media module (media library design spec §6, Task 7): browse,
    # upload, edit and delete library images, all through `Media::Upload`/
    # `Save`/`Destroy`. `index` is the grid (search, filters, pagination);
    # `show` is one image's detail panel; `create` is the grid's own
    # multi-file upload (`admin--media--upload`, one request per file, per
    # the global constraints' own ruling); `update`/`destroy` save/delete.
    # `resources :media` singularizes to "medium" for its member routes
    # (`admin_medium_path`) -- the plain, if slightly odd-looking, Rails
    # default for this one English word, left as-is rather than overridden
    # with an `:as` this app has no other resource needing.
    resources :media, only: %i[index show create update destroy]

    # Trash (trash spec §7). `:type` is page|post|media -- one screen for
    # three models, so the item is addressed by type and id rather than by a
    # resource per model. The constraint is what turns any other `:type`
    # into a routing 404 before `Admin::TrashController` is ever reached.
    get "trash", to: "trash#index", as: :trash
    delete "trash", to: "trash#empty", as: :empty_trash
    # A bulk trash's Undo (Task 17): restores exactly the posts it names.
    post "trash/restore_many", to: "trash#restore_many", as: :restore_many_trash
    post "trash/:type/:id/restore", to: "trash#restore", as: :restore_trash_item, constraints: { type: /page|post|media/ }
    delete "trash/:type/:id", to: "trash#purge", as: :trash_item, constraints: { type: /page|post|media/ }

    # "Still correct — mark up to date" for an outdated translation (translation helpers
    # spec §3.4/§4): one endpoint for every translatable record kind, named
    # by `record_type`/`record_id` in the params (the editor's button posts
    # them in its `formaction`), the way the trash addresses its items by
    # type rather than one nested route per model.
    post "translations/confirm", to: "translation_confirmations#create", as: :translation_confirmation

    # The Translations matrix (design pass round 2, handoff §4.4): every item
    # that needs work in any target language, one column per language,
    # optionally narrowed by `?type=page|post|media|settings` and
    # `?language=` and paged by `?page=`. A plain
    # `get` rather than `resources :translations, only: :index`, so the
    # AI suggestion action (Task 8) can join the same controller on a
    # route of its own without a resource's implied member routes.
    get "translations", to: "translations#index", as: :translations

    # AI translation suggestions (translation helpers spec §6.4): the
    # editor's Translate buttons post the record (`record_type`/
    # `record_id`, like the confirm endpoint above), `fields[]`, the target
    # `locale` and `inputs[field]` (the input each suggestion is for), and
    # get Turbo Streams back. A POST although nothing is saved: it spends
    # the provider's quota and records an `ai.translated` event.
    post "translations/suggest", to: "translations#suggest", as: :translation_suggestions

    # The internal-link picker's own search (design spec §4.1/§4.2): a
    # `GET`, not nested under `pages`/`posts` -- it searches across both at
    # once (`?type=` narrows to one), so there is no single owning resource
    # to nest it under the way `content_blocks` nests under `pages`.
    get "link_targets", to: "link_targets#index"

    # The Posts module (cs-studio spec §4.1/§5.2): a flat, filterable list
    # (no tree column of its own -- a post has no parent/child structure the
    # way a page does) plus the post editor. `member` adds the same three
    # publish-state actions the page editor's own record header posts to
    # (Publish now / Unpublish / Schedule…, `Admin::PagesController`'s own
    # comment explains why each is a one-shot POST kept deliberately outside
    # the post form's own autosave, not folded into `update`).
    # The posts list's bulk bar (Task 17): publish or trash the ticked posts,
    # one `Posts::Bulk` call. Declared before the resource so "bulk" can never
    # be read as a post id.
    post "posts/bulk", to: "posts#bulk", as: :posts_bulk
    resources :posts, only: %i[index new create show update destroy] do
      member do
        post :publish
        post :unpublish
        post :schedule
      end
    end

    # The Tags module (cs-studio spec §4.1/§5.3): a flat list with no
    # `:show`/`:new`/`:create` of its own -- a tag has no editor screen, only
    # an inline rename (`:update`), a delete (`:destroy`) and a merge into
    # another tag (`merge`, `Tags::Merge`) from the list itself; new tags are only ever created in passing, through a post's own
    # `tag_names` (`Posts::Save`).
    # The post editor's tag chip input asks this for suggestions
    # (`Admin::TagSuggestionsController`): needs `posts.read`, not the Tags
    # module's `tags.manage`, and `suggest` is not a tag id (`resources :tags`
    # has no `show`, so the two paths can't collide).
    get "tags/suggest", to: "tag_suggestions#index", as: :tag_suggestions

    resources :tags, only: %i[index update destroy] do
      member { post :merge }
    end

    # The Settings module (cs-studio spec §6.1, Task 8): the `SiteSetting`
    # singleton's own autosaving form (title, tagline, logo, social links,
    # default language) -- `resource` (singular), like the page tree's own
    # `resource :tree`, since there's exactly one settings row to show or
    # update, never a collection or an `:id` to route on.
    resource :settings, only: %i[show update] do
      # Translation helpers spec §6.2: checks the saved AI provider, model
      # and key with one tiny request, answered inline as a Turbo Stream.
      post :test_ai_connection
      # The API key's own save (PATCH) and remove (DELETE), `Admin::AiKeysController`:
      # instant actions beside the Settings form, never part of it (the key is
      # never in the form's data, so it can't be counted as a pending change or
      # sent with the rest).
      resource :ai_key, only: %i[update destroy]
    end

    # Languages (cs-studio spec §6.1; round 3, Task 6 moved them INTO the
    # Settings screen as its `#languages` card). Still under "settings" by
    # *path* only (`scope`, not `namespace`: a plain `Admin::LanguagesController`).
    # What is left is the card's INSTANT actions, each answering with a 303 back
    # to the card: `create` is `Locales::Enable`, `destroy` `Locales::Disable`
    # (one language at a time, by its code as `:id`), `make_default`
    # `Locales::MakeDefault`. The order and fallbacks are not here: they are
    # fields of the Settings form (`Settings::Save`'s `languages:`). The old
    # screen's URL redirects (301) to the card, so bookmarks and links keep working.
    scope "settings", as: "settings" do
      get "languages", to: redirect(status: 301) { |_params, request|
        query = request.query_string.presence
        "#{request.path.sub(%r{/languages(?:/|\.[^/]*)?\z}, "")}#{"?#{query}" if query}#languages"
      }, as: :languages_screen
      resources :languages, only: %i[create destroy]
      patch "languages/:id/default", to: "languages#make_default", as: :default_language
    end

    # The Users module (cs-studio spec §6.1, Task 8): list, new/create,
    # edit/update (email, and a password only when one was typed --
    # `Users::Save`), destroy (refused for the last user, `Users::Destroy`
    # -- `Admin::UsersController#destroy` is also where deleting *yourself*
    # ends your own session, since only the controller knows which request
    # this is). Invites stay on the roadmap (spec §6.1) -- there is no
    # separate "invite" action here.
    # The group editor's member chip input asks this for suggestions
    # (`Admin::UserSuggestionsController`, needs `groups.manage`); declared before
    # `resources :users` so `suggest` is never read as a user id.
    get "users/suggest", to: "user_suggestions#index", as: :user_suggestions

    resources :users, only: %i[index new create edit update destroy] do
      # "Make owner…" / "Remove owner rights…" (round 3 Task 12, D18): an instant
      # action of its own, `owner=1|0`, answered by `Users::Save` like any other
      # change to a user -- never a field of the editor's form.
      member { patch :owner }
    end

    # The Groups module (access-control design spec §5): the list, the
    # editor (name, description, members, the permission matrix) and
    # delete (`Groups::Destroy`, which revokes the group's tokens). No
    # `:show` -- the editor is the group's page.
    resources :groups, only: %i[index new create edit update destroy]

    # "Your account" (access-control design spec §5; the notes handoff's
    # decisions 25 and 38): the signed-in user's own account, open to every
    # user -- unlike the Users module, which needs `users.manage`. Singular:
    # it's always *your* account. The page is `account`. It began as "Change
    # my password" at `account/password`, an address that named one of its
    # three cards: a GET of that one now moves to the page for good (a 301,
    # `accounts#moved`), and the Password card is `#password` there. The two
    # forms post where they always did -- `account/password` (which keeps
    # the name `admin_account_password_path`) and `account/profile` -- so a
    # non-GET is never redirected.
    get "account", to: "accounts#edit", as: :account
    get "account/password", to: "accounts#moved", as: nil
    patch "account/password", to: "accounts#update", as: :account_password
    patch "account/profile", to: "accounts#update_profile", as: :account_profile

    # "Connect an AI assistant" (design spec §6.1, Task 9): the MCP bearer
    # tokens. No `:new`/`:show` -- "Create token" is one button on the list
    # that POSTs straight to `create`, and `create` *renders* the one-time
    # reveal itself (never a redirect to a `show`, which would need the raw
    # token to survive a second request somewhere -- see `Admin::
    # ApiTokensController#create`). `destroy` is revoke
    # (`ApiTokens::Revoke`): the row stays, marked revoked, for the list's
    # own "last used / IP" history.
    resources :api_tokens, only: %i[index create destroy]

    # System status and the mind graph (design spec §6.1, Task 9): one
    # read-only screen each, `resource` (singular) since neither has an
    # `:id` to route on. "Run again" on the status screen is a plain reload
    # of `show` -- `Setup::SystemCheck` runs on every request.
    resource :system_status, only: :show, controller: :system_status
    # `data` and `search` are the mind graph screen's own JSON reads (mind
    # graph canvas spec §3.1): the graph, global or around `post=` / `tag=`,
    # and the search field's rows.
    resource :mind_graph, only: :show, controller: :mind_graph do
      get :data, defaults: { format: :json }
      get :search, defaults: { format: :json }
    end

    # The audit log (access-control design spec §5 "Audit log module",
    # Task 9): a paginated, filterable list plus one event's own page.
    # `resources` (plural, unlike `system_status`/`mind_graph` above) since
    # each row has its own `:id` to route `show` on -- but only `:index`/
    # `:show`: `Audit::Event` is append-only (its own class comment), never
    # created, edited or destroyed through a CS Studio form.
    resources :audit_events, only: %i[index show]

    # "Create starter pages" on the Pages home (design spec §6.1, Task 9):
    # one POST, `StarterContents::Add`, idempotent.
    resources :starter_contents, only: :create

    # A person's own inbox (notes spec §5): the full list, "Mark all read",
    # and the three parts a page shows of it, each with its own GET so a tab
    # can fetch that part again by itself (`turbo-frame#notes-for-you`,
    # `turbo-frame#notes-open-threads`, the sidebar's `#sidebar-badge-dashboard`).
    # None of these words can be taken for a record's notes below: that scope
    # needs `page`, `post` or `media` and an id.
    get "notes", to: "note_inbox#index", as: :notes
    post "notes/read", to: "note_inbox#read", as: :read_notes
    get "notes/card", to: "note_inbox#card", as: :notes_card
    get "notes/open_threads", to: "note_inbox#open_threads", as: :open_note_threads
    get "notes/unread", to: "note_inbox#unread", as: :unread_notes, defaults: { format: :json }
    # One delivery of the viewer's own, as data (notes spec §6.1, §6.4): what
    # a tab asks for when a signal names its id, before it says anything.
    get "notes/deliveries/:id", to: "note_inbox#delivery", as: :note_delivery, constraints: { id: /\d+/ }, defaults: { format: :json }

    # The dashboard is CS Studio's home (dashboard spec §3-§4, Task 2):
    # quick create, "Your drafts", "Going live next", "Needs translation"
    # and "Recent activity", open to every signed-in user. The Pages module -- the tree and its own editor -- lives at
    # its own `/pages` (`resources :pages` above), no longer at the root.
    root to: "dashboard#show"
    # Presence (presence spec §5): who else has a record open, and which of a
    # list's records have someone here. Two reads, both through the read
    # scope; the writes are a channel's (`Presence::Channel`). `here` comes
    # first and its words can not be taken for a kind below.
    get "presence/here", to: "presence#here", as: :presence_here, defaults: { format: :json }
    get "presence/:kind/:id", to: "presence#show", as: :record_presence, constraints: { kind: /page|post|media/, id: /\d+/ }
    # Live editing (live-editing spec §3.2): the parts an open page or post
    # editor fetches when it is told something changed, each through the read
    # scope: a page's block list, one block, the record's own form. Hung under
    # the record like notes' and presence's, but `kind` is only `page|post`:
    # the library has no editor of this shape, and a `media` here would be a
    # route that can only answer 404. `block_id` is digits, so `blocks` and
    # `blocks/:block_id` can not be taken for each other.
    scope "editing/:kind/:id", constraints: { kind: /page|post/, id: /\d+/ } do
      get "blocks", to: "editing#blocks", as: :editing_blocks
      get "blocks/:block_id", to: "editing#block", as: :editing_block, constraints: { block_id: /\d+/ }
      get "record", to: "editing#record", as: :editing_record
      # A save is a claim (live-editing spec §4.2): the tab takes a subject ahead
      # of its first save, and lets it go. `block_id` is optional (absent: the
      # record itself); a block that is not this record's is a 404.
      post "claim", to: "editing#claim", as: :editing_claim
      post "release", to: "editing#release", as: :editing_release
      # Taking over (spec §4.4): the requester asks, the holder's tab hands over.
      post "take_over", to: "editing#take_over", as: :editing_take_over
      post "hand_over", to: "editing#hand_over", as: :editing_hand_over
    end
    # Notes on content (notes spec §3.4, §4). Everything about one record's
    # notes hangs under that record -- `/notes/page/3`, `/notes/post/8`,
    # `/notes/media/5` -- so a controller finds the container through the read
    # scope first and a thread only among that container's: a thread is never
    # found by its id alone. Each part of the notes UI has its own GET here
    # (the list, one thread, the resolved ones, the counts), which is what a
    # live signal asks the browser to fetch again.
    scope "notes/:container_type/:container_id", constraints: { container_type: /page|post|media/, container_id: /\d+/ } do
      get "", to: "notes#index", as: :record_notes
      get "resolved", to: "notes#resolved", as: :resolved_record_notes
      get "counts", to: "notes#counts", as: :record_note_counts, defaults: { format: :json }
      get "threads/:id", to: "note_threads#show", as: :record_note_thread, constraints: { id: /\d+/ }
      # The writes (notes spec §3.5), each an ordinary Turbo form inside
      # `turbo-frame#notes`. A thread's six changes share one action: the
      # segment is the whole request, so nothing about it is read from a
      # parameter (`Admin::NoteThreadsController::CHANGES`).
      get "mentions", to: "note_mentions#index", as: :record_note_mentions, defaults: { format: :json }
      # The record's open threads as data, for the mind graph's card (notes
      # spec §4.4). It shares its path with the POST below, which the card
      # sends too, and has a name of its own because two routes can't share
      # one: `admin_record_note_threads_data_path`.
      get "threads", to: "note_threads#index", as: :record_note_threads_data, defaults: { format: :json }
      post "threads", to: "note_threads#create", as: :record_note_threads
      post "threads/:id/:change", to: "note_threads#change", as: :change_record_note_thread,
        constraints: { id: /\d+/, change: /resolve|reopen|pin|unpin|follow|unfollow/ }
      post "threads/:thread_id/messages", to: "note_messages#create", as: :record_note_messages, constraints: { thread_id: /\d+/ }
      patch "threads/:thread_id/messages/:id", to: "note_messages#update", as: :record_note_message, constraints: { thread_id: /\d+/, id: /\d+/ }
      delete "threads/:thread_id/messages/:id", to: "note_messages#destroy", constraints: { thread_id: /\d+/, id: /\d+/ }
      # A reaction on one message: a toggle of the viewer's own (notes spec D10).
      post "threads/:thread_id/messages/:id/reactions", to: "note_reactions#create", as: :record_note_message_reactions,
        constraints: { thread_id: /\d+/, id: /\d+/ }
      # A file of one message (notes spec D15, §3.6): the ONLY address a
      # note's file has. Its id is an attachment's, looked up among that
      # message's, of that thread, of this record -- never a blob's key or a
      # signed id, and no Active Storage URL of one is ever rendered.
      get "threads/:thread_id/messages/:message_id/files/:id", to: "note_files#show", as: :record_note_file,
        constraints: { thread_id: /\d+/, message_id: /\d+/, id: /\d+/ }
    end

    # Quick draft (dashboard spec §4.1): a title and a content type, saved
    # through `Posts::Save` as an unpublished post, then opened in the
    # post editor.
    post "dashboard/draft", to: "dashboard#create_draft", as: :dashboard_draft
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # First-run setup wizard (design spec 2026-09-26 §4). SetupController
  # itself 404s once setup is complete.
  get "setup", to: "setup#index", as: :setup
  get "setup/:step", to: "setup#show", as: :setup_step
  patch "setup/:step", to: "setup#update"

  # The MCP server (design spec section 10), bearer-token authenticated
  # (McpController#authenticate) -- declared here, before the public-site
  # catch-all below, or "/mcp" would be swallowed as a page path instead.
  post "mcp", to: "mcp#create"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Signed-in preview of unpublished pages and posts (spec §6.4) -- its own
  # URL space, so the public routes below can stay session-free and cacheable.
  # Two routes for the same reason the public site has two: an optional
  # `(/:locale)` would leave "about" in /preview/about to be read as a locale.
  get "preview/:locale(/*path)", to: "preview#show", constraints: LocaleRouteConstraint,
    defaults: { path: "" }, format: false, as: :localized_preview
  get "preview(/*path)", to: "preview#show", defaults: { path: "" }, format: false, as: :preview

  # Every locale is reachable under its own prefix (e.g. /de/about), including
  # whichever one is currently the site's default -- but a default-locale
  # prefix isn't the *canonical* URL for that content; PagesController
  # redirects it to the unprefixed route below, since SiteSetting's own
  # default_locale is a runtime setting this route can't see.
  #
  # Declared before the unprefixed routes below so an explicit "/de/..."
  # always matches here first: Rails tries routes in declaration order, and
  # "de" satisfies this route's locale constraint before the catch-all ever
  # gets a chance to read it as a page path instead.
  #
  # `format: false` suppresses the `(.:format)` group Rails otherwise appends
  # to every route. The site serves exactly one representation of a page, so
  # there is no format to negotiate -- and leaving the group in place breaks
  # this route in both directions, because a dot in the final segment is what
  # triggers it:
  #
  #   - "/de/about.json" on a real page still matches, so the controller finds
  #     the page and renders `show` in a format that has no template.
  #     `ActionView::MissingTemplate` is absent from
  #     `ActionDispatch::ExceptionWrapper.rescue_responses`, so it is mapped to
  #     no status and reaches the visitor as an uncaught 500 -- on a URL any
  #     crawler can construct.
  #   - A page whose slug legitimately contains a dot ("/v1.0") has its own
  #     trailing characters sliced off into `params[:format]`, so it 404s at
  #     the exact path `Page#full_path` publishes and config/sitemap.rb hands
  #     to search engines.
  #
  # The glob segment is wrapped in an optional group rather than left bare: a
  # `defaults: { path: "" }` alone does *not* make `*path` optional -- Journey
  # still requires at least one character for it, so "/de/" (which Rails
  # normalizes to "/de") would raise a routing error and that locale's root
  # would be unreachable. `(/*path)` makes the segment genuinely optional.
  # `constraints: LocaleRouteConstraint` (not a fixed regex): which locales
  # this route actually matches is a runtime setting (site_settings.locales,
  # spec §4.4), so it can't be hard-coded here the way `:path`'s absence of a
  # constraint can. `LocaleRouteConstraint#matches?` calls `Locales.enabled?`
  # per request; a locale that fails it is not an error -- the router simply
  # tries the next route, which is exactly what lets "/fr/about" fall through
  # to the unprefixed catch-all below (and then 404 there, since "fr/about"
  # is not itself a page) the moment "fr" is disabled, with no deploy needed.
  get ":locale(/*path)", to: "pages#show", constraints: LocaleRouteConstraint, as: :localized_page,
    defaults: { path: "" }, format: false

  # No locale prefix at all: served in the site's current default locale
  # (SiteSetting#default_locale, read per request by PagesController). Two
  # routes rather than one optional-locale route, deliberately -- a single
  # `"(/:locale)(/*path)"` pattern leaves Rails to decide for itself whether
  # a first segment like "de" is a locale or a page slug, which is exactly
  # the kind of routing ambiguity `format: false` above was already added to
  # close off one instance of; two separate, explicitly-ordered routes have
  # no such ambiguity to resolve.
  #
  # `root` on its own (rather than folding "/" into the `*path` glob below)
  # because an unwrapped `get "*path"` requires at least one character, the
  # same Journey behavior the locale route above works around with `(/*path)`
  # -- but here there's no static segment ahead of the glob to wrap it against,
  # so the homepage gets its own route instead.
  #
  # The constraint (final fix wave, C) keeps Active Storage's own URLs out of
  # this catch-all: Rails draws the Active Storage routes *after* this file,
  # so without it `/rails/active_storage/blobs/...` -- every image a page,
  # post or rich-text body embeds -- was routed here and answered 404.
  root to: "pages#show", format: false
  get "*path", to: "pages#show", as: :page, format: false,
    constraints: ->(request) { !request.path.start_with?("#{ActiveStorage.routes_prefix}/") }
end
