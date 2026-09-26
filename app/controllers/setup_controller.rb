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

  before_action :require_setup_pending
  before_action :load_step, only: %i[show update]
  before_action :require_step_access, only: %i[show update]

  rate_limit to: 10, within: 3.minutes, only: :update, store: RATE_LIMIT_STORE,
    if: -> { params[:step] == "token" },
    with: -> { redirect_to setup_step_path("token"), alert: "Too many attempts. Try again in a few minutes." }

  helper_method :step_label, :optional_step?, :next_step

  def index
    redirect_to setup_step_path(first_step)
  end

  def show
    case @step
    when "system_check" then @results = Setup::SystemCheck.run
    when "admin" then @user = User.new
    when "site", "languages" then @site_setting = SiteSetting.instance
    when "review"
      @site_setting = SiteSetting.instance
      @starter_added = StarterContent.added?(locale: @site_setting.default_locale)
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

    def first_step
      return "site" if User.exists?

      session[:setup_token_verified] ? "system_check" : "token"
    end

    def next_step
      STEPS[STEPS.index(@step) + 1]
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
    def update_admin
      @user = User.new(params.expect(user: [ :email_address, :password, :password_confirmation ]))

      created = User.transaction do
        User.connection.execute("LOCK TABLE users IN SHARE ROW EXCLUSIVE MODE")
        User.none? && @user.save
      end

      if created
        start_new_session_for(@user)
        session.delete(:setup_token_verified)
        redirect_to setup_step_path("site")
      elsif User.exists?
        redirect_to new_session_path, alert: "An admin account already exists. Sign in to continue setup."
      else
        render :admin, status: :unprocessable_entity
      end
    end

    def update_site
      @site_setting = SiteSetting.instance

      if @site_setting.update(site_params)
        redirect_to setup_step_path("languages")
      else
        render :site, status: :unprocessable_entity
      end
    end

    # The form always renders a few name/URL rows; a row missing either half
    # is dropped rather than saved as a broken link. A request that omits the
    # social_links key entirely (no rows submitted at all, e.g. a crafted or
    # partial PATCH) leaves the previously saved links alone rather than
    # wiping them out.
    def site_params
      permitted = params.expect(site_setting: [ :title, :tagline, :logo, social_links: [ [ :name, :url ] ] ])
      return permitted unless permitted.key?(:social_links)

      rows = Array(permitted.delete(:social_links))
      links = rows.filter_map do |row|
        name, url = row[:name].to_s.strip, row[:url].to_s.strip
        [ name, url ] if name.present? && url.present?
      end
      permitted.merge(social_links: links.to_h)
    end

    def update_languages
      @site_setting = SiteSetting.instance

      if @site_setting.update(default_locale: params.dig(:site_setting, :default_locale))
        redirect_to setup_step_path("mcp_token")
      else
        render :languages, status: :unprocessable_entity
      end
    end

    # Rendered, not redirected: the raw token exists only in this response and
    # must never pass through the session or flash. no-store keeps it out of
    # the back/forward cache too, so navigating away doesn't leave the still-
    # valid raw token one "back" button press away from resurfacing.
    def update_mcp_token
      _token, @raw_token = ApiToken.generate!(Current.user)
      response.set_header("Cache-Control", "no-store")
      render :mcp_token_created
    end

    def update_starter_content
      StarterContent.create_pages_and_posts!(locale: SiteSetting.instance.default_locale)
      redirect_to setup_step_path("review"), notice: "Starter content added."
    end

    def update_review
      Setup.complete!
      redirect_to Avo.configuration.root_path, notice: "Setup complete."
    end
end
