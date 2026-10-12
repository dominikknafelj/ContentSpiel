# The first-run setup wizard (design spec 2026-09-26 §3-§4). Every step
# persists as soon as it's submitted, so an admin who closes the browser can
# sign in again and resume. Access:
#   - no user yet: anyone who entered the setup token this session, and only
#     the steps up to creating the admin;
#   - admin exists: only a signed-in user;
#   - setup completed: 404.
class SetupController < ApplicationController
  STEPS = %w[token system_check admin site languages mcp_token starter_content review].freeze
  PRE_ADMIN_STEPS = %w[token system_check admin].freeze
  OPTIONAL_STEPS = %w[system_check mcp_token starter_content].freeze
  LABELS = {
    "token" => "Setup token", "system_check" => "System check", "admin" => "Admin account",
    "site" => "Site identity", "languages" => "Languages", "mcp_token" => "MCP token",
    "starter_content" => "Starter content", "review" => "Review"
  }.freeze

  # The rate limit needs a real store, and Rails.cache is :null_store in test
  # (every write a no-op, so the limit would never trip there). Per-process
  # memory is enough: setup runs once, against one server.
  RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new

  allow_unauthenticated_access
  layout "setup"

  # Overrides ApplicationController's `:admin` default (spec §7.1) -- setup
  # writes (the site, languages, MCP token, starter content) run before an
  # admin session necessarily exists, so they're attributed to their own
  # channel rather than misreported as `:admin`.
  before_action { Current.channel = :setup }

  before_action :require_setup_pending
  before_action :load_step, only: %i[show update]
  before_action :require_step_access, only: %i[show update]
  # Final fix wave (Important 3): once the owner exists every step runs
  # signed in (`require_step_access`), and its writes are attributed to
  # that owner -- `ApplicationController#set_current_actor` ran before the
  # session was resumed, so `Current.actor` is still nil here. Before the
  # admin step there's nobody to attribute to: those writes stay the
  # trusted nil actor on `:setup`.
  before_action :act_as_signed_in_user, only: %i[show update]

  rate_limit to: 10, within: 3.minutes, only: :update, store: RATE_LIMIT_STORE,
    if: -> { params[:step] == "token" },
    with: -> { redirect_to setup_step_path("token"), alert: "Too many attempts. Try again in a few minutes." }

  helper_method :step_label, :optional_step?, :next_step, :previous_step

  def index
    redirect_to setup_step_path(first_step)
  end

  def show
    case @step
    when "system_check" then @results = Setup::SystemCheck.run(request_ssl: request.ssl?)
    when "admin" then @user = User.new
    when "site", "languages" then @site_setting = Current.site
    when "review"
      @site_setting = Current.site
      @starter_added = StarterContent.added?(locale: @site_setting.default_locale)
      @mcp_token_name = session[:setup_token_name]
    end

    render @step
  end

  def update
    case @step
    when "token" then update_token
    when "admin" then update_admin
    when "site" then update_site
    when "languages" then update_languages
    when "mcp_token" then update_mcp_token
    when "starter_content" then update_starter_content
    when "review" then update_review
    else head :not_found
    end
  end

  private
    def require_setup_pending
      head :not_found unless Setup.required?
    end

    def load_step
      @step = params[:step]
      head :not_found unless STEPS.include?(@step)
    end

    def require_step_access
      if User.none?
        return if @step == "token"
        return redirect_to(setup_step_path("token")) unless session[:setup_token_verified]
        redirect_to(setup_step_path("admin")) unless PRE_ADMIN_STEPS.include?(@step)
      else
        return request_authentication unless authenticated?
        redirect_to(setup_step_path("site")) if %w[token admin].include?(@step)
      end
    end

    def act_as_signed_in_user
      Current.actor = Current.user if Current.user
    end

    def first_step
      return "site" if User.exists?

      session[:setup_token_verified] ? "system_check" : "token"
    end

    def next_step
      STEPS[STEPS.index(@step) + 1]
    end

    # The step a "Back" link goes to: nil on the first step, and on "site",
    # whose predecessor (creating the admin) can't be revisited once the
    # account exists -- `require_step_access` bounces a signed-in visitor off
    # "token" and "admin".
    def previous_step
      index = STEPS.index(@step)
      return if index.zero? || @step == "site"

      STEPS[index - 1]
    end

    def step_label(step) = LABELS.fetch(step)

    def optional_step?(step) = OPTIONAL_STEPS.include?(step)

    def update_token
      if Setup::Token.valid?(params[:token])
        session[:setup_token_verified] = true
        redirect_to setup_step_path("system_check")
      else
        flash.now[:alert] = "That setup token doesn't match. Copy it from the server log."
        render :token, status: :unprocessable_entity
      end
    end

    # The lock closes the window between two browsers submitting this step at
    # the same moment: only the first sees `User.none?` and becomes the admin;
    # the second is sent to sign in.
    #
    # The first account is the site's owner (access-control design spec
    # §6): every later setup step writes through permission-checked services
    # as this user, and a user in no group may do nothing. It's created
    # through `Users::Save` like any other account (final fix wave,
    # Important 3), so it gets its `user.created` event -- by the trusted
    # nil actor on `:setup`, since nobody is signed in yet. `Users::Save`'s
    # own transaction joins this one, inside the lock.
    def update_admin
      attributes = params.expect(user: [ :email_address, :password, :password_confirmation ]).to_h.merge(owner: true)
      result = nil

      User.transaction do
        User.connection.execute("LOCK TABLE users IN SHARE ROW EXCLUSIVE MODE") # sql: neither Active Record nor Arel has a table lock; a constant statement
        result = Users::Save.call(User.new, attributes: attributes, actor: nil) if User.none?
      end

      if result&.ok?
        start_new_session_for(result.record)
        # A sign-in like any other, so audited like one (`Admin::
        # SessionsController#create`): `session.created`, the user as actor
        # and subject, on this request's `:setup` channel. Without it the
        # founding owner -- signed in here, never through the sign-in form --
        # has no sign-in on record, and the Users list (`Users::LastSignIn`
        # reads these events) says "Never" on a fresh install.
        Current.actor = result.record
        Audit.record("session.created", subject: result.record)
        session.delete(:setup_token_verified)
        redirect_to setup_step_path("site")
      elsif result.nil?
        redirect_to admin_sign_in_path, alert: "An admin account already exists. Sign in to continue setup."
      else
        @user = result.record
        render :admin, status: :unprocessable_entity
      end
    end

    def update_site
      @site_setting = Current.site

      site = site_params.to_h
      translated = site.extract!(*Settings::Save::TRANSLATED.map(&:to_s))

      # The title and tagline are translated (translation helpers spec §5)
      # and typed here in the site's default language -- which the next
      # step may still change, taking them along (`SiteSetting#carry_
      # translations_into_new_default_locale`).
      if Settings::Save.call(@site_setting, attributes: site, translations: { @site_setting.default_locale => translated }).ok?
        redirect_to setup_step_path("languages")
      else
        render :site, status: :unprocessable_entity
      end
    end

    # The form always renders a few name/URL rows; a row missing either half
    # is dropped rather than saved as a broken link (`SiteSetting#social_
    # link_rows=`, Task 8 -- moved out of here so `Admin::SettingsController`
    # shares the exact same normalisation instead of hand-keeping its own
    # copy). A request that omits the social_links key entirely (no rows
    # submitted at all, e.g. a crafted or partial PATCH) leaves the
    # previously saved links alone rather than wiping them out.
    def site_params
      permitted = params.expect(site_setting: [ :title, :tagline, :logo, social_links: [ [ :name, :url ] ] ])
      return permitted unless permitted.key?(:social_links)

      permitted[:social_link_rows] = permitted.delete(:social_links)
      permitted
    end

    # Writes the chosen default plus any additional languages as
    # `site_settings.locales` (spec §4.4) -- unlike every other step, this one
    # can change what `Locales.enabled` returns, so every page and post needs
    # a URL recomputed in whichever languages just became enabled (or lost
    # one that just left) before the next step renders. `extra_locales` has
    # no backing column -- it only exists as a form field -- so it's read
    # straight off `params` rather than assigned to `@site_setting` directly.
    def update_languages
      @site_setting = Current.site
      permitted = params.expect(site_setting: [ :default_locale, extra_locales: [] ])
      codes = ([ permitted[:default_locale] ] + Array(permitted[:extra_locales])).uniq.compact_blank

      result = Settings::Save.call(@site_setting,
        attributes: { default_locale: permitted[:default_locale], locales: codes.map { |code| { "code" => code } } })

      if result.ok?
        PublicSite::Paths.rebuild!
        redirect_to setup_step_path("mcp_token")
      else
        render :languages, status: :unprocessable_entity
      end
    end

    # Rendered, not redirected: the raw token exists only in this response and
    # must never pass through the session or flash. no-store keeps it out of
    # the back/forward cache too, so navigating away doesn't leave the still-
    # valid raw token one "back" button press away from resurfacing.
    #
    # The token's *name* is required (round 3 decision D2): `name:` is always a
    # String, so a missing or blank field is "Name can't be blank" (422, back on
    # the form with what was typed) and not a default "Token 1". The name --
    # never the token -- is kept in the session for the review step's row.
    def update_mcp_token
      # The first account is an owner, so its token gets the Admin group
      # (it can be narrowed to another group in CS Studio later).
      admin = AccessControl::Group.find_by!(name: AccessControl::Seeds::ADMIN_NAME)
      name = params[:token_name].to_s
      result = ApiTokens::Issue.call(Current.user, group: admin, name: name)

      unless result.ok?
        @token_name = name
        @token_error = result.errors.to_sentence
        return render :mcp_token, status: :unprocessable_entity
      end

      token, @raw_token = result.record
      session[:setup_token_name] = token.name
      response.set_header("Cache-Control", "no-store")
      render :mcp_token_created
    end

    # `StarterContents::Add` (locked and idempotent, final fix wave,
    # P23): the same locked, re-checked path CS Studio's "Create starter
    # pages" takes, so a double submit can't race itself into a
    # duplicate-slug 500. A failure is shown on this step (422), like any
    # other step's form error.
    def update_starter_content
      result = StarterContents::Add.call

      if result.ok?
        redirect_to setup_step_path("review"), notice: result.record ? "Starter content added." : "Starter content was already there."
      else
        flash.now[:alert] = "#{result.errors.to_sentence}."
        render :starter_content, status: :unprocessable_entity
      end
    end

    # The homepage always exists when setup is over, so "/" is never a 404 on
    # a new site (`StarterContents::EnsureHome`, run as the signed-in owner);
    # it and the marker that ends setup commit together.
    def update_review
      SiteSetting.transaction do
        StarterContent.raise!(StarterContents::EnsureHome.call(locale: Current.site.default_locale))
        Setup.complete!
      end
      # CS Studio is where every sign-in lands now (cs-studio spec §3) --
      # finishing setup is no exception, even though the admin who just
      # walked through this wizard is already signed in from `update_admin`
      # above.
      redirect_to admin_root_path, notice: "Setup complete."
    end
end
