require "test_helper"

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
