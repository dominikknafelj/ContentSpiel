require "test_helper"
require_relative "../support/source_code"

# With ADMIN_HOST set, the backend (every route under /<ADMIN_PATH>/) answers
# on the admin host alone and the public site's pages and form sends on every
# other host; on the wrong host either is the public 404, never a redirect
# that would name the other host. `/up` and Active Storage answer on both.
class AdminHostTest < ActionDispatch::IntegrationTest
  PUBLIC_ADDRESS = "https://docs.example.org".freeze
  ADMIN_ADDRESS = "https://studio.example.internal".freeze
  SITE_ROUTES = [ "GET /", "GET /:locale(/*path)", "GET /*path", "POST /forms/:form_id" ].freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @root = Page.create!(title: "Home", slug: "", published_at: 1.day.ago)
    @about = Page.create!(parent: @root, title: "About", published_at: 1.day.ago)
  end

  test "every backend route is unknown on the public host" do
    both_hosts do
      backend = Rails.application.routes.routes.select { |route| under_prefix?(route) && route.verb.present? }
      assert_not_empty backend

      backend.each do |route|
        path = sample_path(route)
        assert_unknown_or_page "http://docs.example.org#{path}", route.verb, allowed: %w[pages], route: route
      end
    end
  end

  test "every public route is unknown on the admin host" do
    both_hosts do
      site = Rails.application.routes.routes.select { |route| SITE_ROUTES.include?("#{route.verb} #{route.path.spec}") }
      assert_equal SITE_ROUTES.size, site.size

      site.each do |route|
        assert_unknown_or_page "http://studio.example.internal#{sample_path(route)}", route.verb, allowed: [], route: route
      end
    end
  end

  test "on the public host the backend answers the public 404, with no redirect" do
    both_hosts do
      host! "docs.example.org"
      [ [ :get, "/cs-studio/sign-in" ], [ :get, "/cs-studio/cable" ], [ :get, "/cs-studio/preview/about" ], [ :post, "/cs-studio/mcp" ] ].each do |verb, path|
        send(verb, path)
        assert_response :not_found, "#{verb.upcase} #{path}"
        assert_nil response.location, "#{verb.upcase} #{path}"
        assert_no_match(/studio\.example\.internal/, response.body)
      end
    end
  end

  test "on the admin host a page path is a 404" do
    both_hosts do
      host! "studio.example.internal"
      get "/"
      assert_response :not_found
      get "/about"
      assert_response :not_found
    end
  end

  test "the admin host is matched as config.hosts matches it" do
    both_hosts do
      host! "Studio.Example.Internal"
      get "/cs-studio/sign-in"
      assert_response :success

      https!
      host! "studio.example.internal:443"
      get "/cs-studio/sign-in"
      assert_response :success
    end
  end

  test "/up answers on both hosts" do
    both_hosts do
      %w[docs.example.org studio.example.internal].each do |host|
        host! host
        get "/up"
        assert_response :success, host
      end
    end
  end

  test "a made width of a library image answers on both hosts" do
    asset = make_renditions!(create_media_asset)
    both_hosts do
      %w[docs.example.org studio.example.internal].each do |host|
        host! host
        get asset.srcset.first.first
        assert_response :success, host
      end
    end
  end

  test "while setup is pending the admin host is sent to the wizard, which answers there" do
    start_fresh_install
    both_hosts do
      host! "studio.example.internal"
      get "/cs-studio"
      assert_redirected_to "http://studio.example.internal/cs-studio/setup"

      # The wizard's index sends on to its first step, on the same host.
      get "/cs-studio/setup"
      assert_redirected_to "http://studio.example.internal/cs-studio/setup/token"
      follow_redirect!
      assert_response :success
    end
  end

  test "a reset mail's link names the admin host" do
    put_mail_state(:working)
    ActionMailer::Base.deliveries.clear
    both_hosts do
      host! "studio.example.internal"
      post "/cs-studio/password", params: { email_address: users(:one).email_address }
      perform_enqueued_jobs while enqueued_jobs.any?

      mail = ActionMailer::Base.deliveries.last
      assert_equal [ users(:one).email_address ], mail.to
      assert_equal "studio.example.internal", URI.parse(mail.text_part.body.to_s[%r{https?://\S+}]).host
    end
  end

  test "the session cookie has no Domain attribute" do
    both_hosts do
      host! "studio.example.internal"
      post "/cs-studio/sign-in", params: { email_address: users(:one).email_address, password: "password" }

      cookie = Array(response.headers["Set-Cookie"]).join("\n")
      assert_match(/session_id=/, cookie)
      assert_no_match(/;\s*domain=/i, cookie)
    end
  end

  test "a password sign-in on the admin host opens CS Studio there" do
    site_settings(:default).update!(passkey_policy: "nobody")
    both_hosts do
      https!
      host! "studio.example.internal"
      post "/cs-studio/sign-in", params: { email_address: users(:one).email_address, password: "password" }
      assert_redirected_to "https://studio.example.internal/cs-studio"

      follow_redirect!
      assert_response :success
      get "/cs-studio/posts"
      assert_response :success
    end
  end

  # Every passkey ceremony runs on the admin host, so the relying party is
  # its address: the id a browser signs for and the origin the server checks.
  test "a passkey signs in on the admin host, under the admin host's relying party" do
    user = User.create!(email_address: "ann@example.org", password: "password12345")
    both_hosts do
      client = fake_authenticator(origin: ADMIN_ADDRESS)
      add_passkey(user, client: client)

      https!
      host! "studio.example.internal"
      post "/cs-studio/sign-in/passkey/options", as: :json
      assert_response :success
      options = response.parsed_body
      assert_equal "example.internal", options.fetch("rpId")

      credential = passkey_assertion(client, challenge: options.fetch("challenge"), user_handle: user.webauthn_id)
      post "/cs-studio/sign-in/passkey", params: { credential: credential }, as: :json
      assert_equal "https://studio.example.internal/cs-studio", response.parsed_body.fetch("location")
      assert_equal "passkey", Session.find_by!(user: user).authenticated_with
    end
  end

  # Review Focus 5: the provider is told the admin host's callback, the
  # state's cookie is the admin path's, and the public host never answers the
  # callback.
  test "with an admin host the redirect URI names it, the callback answers there alone, and the public host's callback is the public 404" do
    with_fake_idp do |idp|
      both_hosts do
        https!
        host! "studio.example.internal"
        post "/cs-studio/sign-in/sso"
        assert_response :see_other, "the start on the admin host sends to the provider"
        callback = "#{ADMIN_ADDRESS}/cs-studio/sign-in/sso/callback"
        assert_equal callback, Rack::Utils.parse_query(URI(response.location).query)["redirect_uri"], "the redirect URI names the admin host"
        cookie = Array(response.headers["Set-Cookie"]).flat_map { |line| line.split("\n") }.find { |line| line.start_with?("cs_sso_state=") }
        assert_includes cookie.downcase, "path=/cs-studio/sign-in/sso", "the state's cookie is the admin path's"
        assert_includes cookie.downcase, "secure", "over HTTPS the state's cookie is Secure"
        assert_no_match(/;\s*domain=/i, cookie, "the state's cookie is the admin host's alone")

        back = idp.authorize(response.location)
        assert back.start_with?("#{callback}?"), "the provider sends the browser back to the admin host"
        get back
        assert_redirected_to "#{ADMIN_ADDRESS}/cs-studio", "the callback answers on the admin host"
        assert_equal "sso", Session.sole.authenticated_with, "the admin host's callback signs in by sso"

        host! "docs.example.org"
        get "/cs-studio/sign-in/sso/callback", params: { code: "x", state: "y" }
        assert_response :not_found, "the public host's callback"
        assert_nil response.location, "the public host's callback names no other host"
        assert_no_match(/studio\.example\.internal/, response.body)
        post "/cs-studio/sign-in/sso"
        assert_response :not_found, "the public host's start"
      end
    end
  end

  test "the registration options on the admin host name the admin host's relying party" do
    both_hosts do
      https!
      host! "studio.example.internal"
      sign_in_as(users(:one))
      post "/cs-studio/account/passkeys/options", as: :json
      assert_response :success
      assert_equal "example.internal", response.parsed_body.dig("rp", "id")
    end
  end

  test "the editor's copy link to a published page names the public host" do
    both_hosts do
      host! "studio.example.internal"
      sign_in_as(users(:one))
      get "/cs-studio/pages/#{@about.id}"
      assert_response :success
      assert_select "[data-admin--ui--clipboard-url-value^='https://docs.example.org/']"
    end
  end

  test "View on site opens the public host" do
    both_hosts do
      host! "studio.example.internal"
      sign_in_as(users(:one))
      get "/cs-studio/pages/#{@about.id}"
      assert_response :success
      assert_select "a[href='https://docs.example.org/about']", text: /View on site/
    end
  end

  # R5: the policy sets neither directive, so it restricts no socket.
  test "the content security policy restricts neither connect-src nor default-src" do
    both_hosts do
      host! "studio.example.internal"
      sign_in_as(users(:one))
      get "/cs-studio"
      policy = response.headers["Content-Security-Policy"].to_s
      assert_not_empty policy
      assert_no_match(/(?:^|;)\s*(?:connect-src|default-src)\b/, policy)
    end
  end

  # R5: Action Cable's same-origin rule (on by default) is what lets the admin
  # host's socket in and every other origin out; a list of origins, or the rule
  # switched off, would change who the socket accepts.
  test "the cable accepts its own origin and no other" do
    assert ActionCable.server.config.allow_same_origin_as_host
    assert_nil Rails.application.config.action_cable.allowed_request_origins
  end

  # A cookie's options often span lines, so the check is not per statement:
  # a `domain:` key (or `:domain` symbol) anywhere in the app's code is refused.
  # None exists today, in a cookie or elsewhere, so there is no allow-list.
  COOKIE_DOMAIN = /\bdomain:|:domain\b|["']domain["']\s*=>/

  test "no cookie is given a domain" do
    offenders = %w[app config lib].flat_map { |root| Rails.root.glob("#{root}/**/*.{rb,erb,rake}") }.select do |path|
      SourceCode.code_of(path.to_s).match?(COOKIE_DOMAIN)
    end
    assert_empty offenders.map { |path| path.relative_path_from(Rails.root).to_s }, "a cookie with a domain would reach the other host"

    assert_match COOKIE_DOMAIN, SourceCode.code_of("x.rb", "cookies.encrypted[:x] = {\n  value: 1,\n  domain: \".x\" }")
    assert_match COOKIE_DOMAIN, SourceCode.code_of("x.rb", "config.session_store :cookie_store,\n  domain: :all")
    assert_no_match COOKIE_DOMAIN, SourceCode.code_of("x.rb", "# domain: :all\ncookies[:x] = 1")
  end

  test "without ADMIN_HOST one host answers both" do
    with_site_address(PUBLIC_ADDRESS) do
      host! "docs.example.org"
      get "/cs-studio/sign-in"
      assert_response :success
      get "/about"
      assert_response :success
    end
  end

  private

  def both_hosts(&block)
    with_site_address(PUBLIC_ADDRESS) { with_admin_address(ADMIN_ADDRESS, &block) }
  end

  def under_prefix?(route)
    spec = route.path.spec.to_s
    prefix = "/#{ContentSpiel::ADMIN_PATH}"
    spec == prefix || spec.start_with?("#{prefix}/", "#{prefix}(")
  end

  # A path the route's pattern would match: every `:param` is 1, every
  # `*glob` x, every optional group dropped.
  def sample_path(route)
    path = route.path.spec.to_s
    path = path.gsub(/\([^()]*\)/, "") while path.include?("(")
    path.gsub(/:\w+/, "1").gsub(/\*\w+/, "x")
  end

  # Recognised as nothing, or (on the public host) as the page catch-all that
  # every unknown path falls through to: either way none of the other host's.
  def assert_unknown_or_page(url, verb, allowed:, route:)
    recognized = Rails.application.routes.recognize_path(url, method: verb)
    assert_includes allowed, recognized[:controller], "#{route.verb} #{route.path.spec} answered on the wrong host: #{recognized.inspect}"
  rescue ActionController::RoutingError
    pass
  end
end
