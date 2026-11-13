require "test_helper"
require "open3"

# Everything the backend answers lives under the admin path
# (`ContentSpiel::ADMIN_PATH`), so that a site owns every other address for its
# own pages and `ADMIN_PATH` is the one place a deployment (a proxy rule, a
# firewall, a bot-check) draws the line between the site and its backend. This
# guard holds that: every route outside `/<ADMIN_PATH>/` is on `PUBLIC`, the
# list of what a visitor or the proxy may ask for, each with the reason it is
# public. A new route outside the prefix fails here until it moves under it or
# is listed with its reason.
#
# It reads `Rails.application.routes.routes`, internal routes included: the
# cable mount is internal, and `bin/rails routes` hides it. What it cannot see
# are routes drawn only in development (`/lookbook`, `/rails/info`,
# `/rails/mailers`), which the test environment does not draw.
class BackendPathsTest < ActiveSupport::TestCase
  SETUP_PENDING = "while setup is pending they send a page load to the wizard or refuse anything else " \
                  "with a 404 (the redirect and the refusal share one spec and verb); once setup is done they answer nothing".freeze
  ACTIVE_STORAGE_READ = "public pages embed these; `ActiveStoragePublicFiles` decides what they serve".freeze
  ACTIVE_STORAGE_WRITE = "drawn because the read helpers share their file; `ActiveStorageWriteRefusal` answers 404 to everyone".freeze

  VIEW_COMPONENTS = "ViewComponent's preview routes, drawn in development and test only, never in production".freeze
  HEALTH_CHECK = "the health check, asked by the proxy".freeze
  SYSTEM_TEST_ENTRYPOINT = "Rails' own entrypoint of the browser tests, drawn in the test environment only".freeze

  # The reasons whose routes answer on every host, ADMIN_HOST or not: the
  # proxy asks `/up` on either name, both hosts embed Active Storage's files,
  # the setup redirect gates CS Studio on the admin host too, and the test
  # routes are never drawn in production. Every other route outside the prefix
  # is the site's and carries `HostRouteConstraint::Site`.
  HOST_FREE = [ SETUP_PENDING, HEALTH_CHECK, ACTIVE_STORAGE_READ, ACTIVE_STORAGE_WRITE, VIEW_COMPONENTS, SYSTEM_TEST_ENTRYPOINT ].freeze

  # Keys are `"VERB spec"`, as `key` writes them.
  PUBLIC = {
    " /" => SETUP_PENDING,
    " /*path" => SETUP_PENDING,
    "GET /" => "the public site's home page",
    "GET /:locale(/*path)" => "the public site's pages, under a language",
    "GET /*path" => "the public site's pages",
    "POST /forms/:form_id" => "a visitor's send of a form",
    "GET /up(.:format)" => HEALTH_CHECK,
    "GET /rails/active_storage/blobs/redirect/:signed_id/*filename(.:format)" => ACTIVE_STORAGE_READ,
    "GET /rails/active_storage/blobs/proxy/:signed_id/*filename(.:format)" => ACTIVE_STORAGE_READ,
    "GET /rails/active_storage/blobs/:signed_id/*filename(.:format)" => ACTIVE_STORAGE_READ,
    "GET /rails/active_storage/representations/redirect/:signed_blob_id/:variation_key/*filename(.:format)" => ACTIVE_STORAGE_READ,
    "GET /rails/active_storage/representations/proxy/:signed_blob_id/:variation_key/*filename(.:format)" => ACTIVE_STORAGE_READ,
    "GET /rails/active_storage/representations/:signed_blob_id/:variation_key/*filename(.:format)" => ACTIVE_STORAGE_READ,
    "GET /rails/active_storage/disk/:encoded_key/*filename(.:format)" => ACTIVE_STORAGE_READ,
    "PUT /rails/active_storage/disk/:encoded_token(.:format)" => ACTIVE_STORAGE_WRITE,
    "POST /rails/active_storage/direct_uploads(.:format)" => ACTIVE_STORAGE_WRITE,
    "GET /rails/view_components(.:format)" => VIEW_COMPONENTS,
    "GET /rails/view_components/*path(.:format)" => VIEW_COMPONENTS,
    "GET /_system_test_entrypoint(.:format)" => SYSTEM_TEST_ENTRYPOINT
  }.freeze

  test "the guard is looking at the routes" do
    set = ActionDispatch::Routing::RouteSet.new
    set.draw do
      scope(ContentSpiel::ADMIN_PATH) { get "inside", to: "x#y" }
      post "export", to: "x#y"
    end
    assert_equal [ "POST /export(.:format)" ], outside(set)
  end

  test "every route outside ADMIN_PATH is on the public list, with its reason" do
    assert_empty outside(Rails.application.routes),
      "these answer outside /#{ContentSpiel::ADMIN_PATH}/: move them under it, or add them to PUBLIC with the reason they are public"
  end

  test "the public list names only routes that exist" do
    drawn = Rails.application.routes.routes.map { |route| key(route) }
    assert_empty PUBLIC.keys - drawn
  end

  test "the cable mount is among the routes the guard reads" do
    assert_includes Rails.application.routes.routes.map { |route| route.path.spec.to_s }, "/#{ContentSpiel::ADMIN_PATH}/cable"
  end

  test "with another ADMIN_PATH every backend address follows" do
    script = 'h = Rails.application.routes.url_helpers; puts [h.preview_path, h.setup_path, h.mcp_path, ActionCable.server.config.url].join(" ")'
    env = { "ADMIN_PATH" => "studio", "RAILS_ENV" => "test", "PGGSSENCMODE" => "disable" }
    output, status = Open3.capture2e(env, "bin/rails", "runner", script)
    assert status.success?, output
    assert_equal "/studio/preview /studio/setup /studio/mcp /studio/cable", output.lines.last.strip
  end

  # Each constraint object is read per request (`SiteAddress.admin`), so the
  # guard holds that the object is on the route whatever ADMIN_HOST says here.
  test "every route under ADMIN_PATH carries the admin host's constraint" do
    backend = Rails.application.routes.routes.select { |route| under_prefix?(route) }
    assert_includes backend.map { |route| route.path.spec.to_s }, "/#{ContentSpiel::ADMIN_PATH}/cable"
    assert_empty backend.reject { |route| constrained_by?(route, HostRouteConstraint::Backend) }.map { |route| key(route) }
  end

  test "every route outside ADMIN_PATH carries the site's constraint unless it is host-free" do
    assert_includes Rails.application.routes.routes.map { |route| key(route) }, "GET /*path"
    assert_empty site_routes_without_constraint(Rails.application.routes),
      "these answer on the admin host too: draw them inside constraints(HostRouteConstraint::Site), " \
      "or give them a reason in PUBLIC that HOST_FREE lists, saying why they answer on every host"
  end

  test "the site's check can fail" do
    set = ActionDispatch::Routing::RouteSet.new
    set.draw do
      constraints(HostRouteConstraint::Site) do
        get "covered", to: "x#y"
        get "own", to: "x#y", constraints: ->(_request) { true }
      end
    end
    assert_equal [ "GET /own(.:format)" ], site_routes_without_constraint(set)
  end

  test "the host check can fail" do
    set = ActionDispatch::Routing::RouteSet.new
    set.draw do
      scope(ContentSpiel::ADMIN_PATH) do
        get "bare", to: "x#y"
        mount ->(_env) { [ 200, {}, [] ] } => "socket", anchor: true
      end
    end
    assert_empty set.routes.select { |route| constrained_by?(route, HostRouteConstraint::Backend) }
  end

  private

  # A route under `constraints(object)` has its app wrapped in
  # `ActionDispatch::Routing::Mapper::Constraints`, a controller route's and a
  # mounted Rack app's (the cable) alike; the wrapper holds the objects.
  def constrained_by?(route, constraint)
    route.app.is_a?(ActionDispatch::Routing::Mapper::Constraints) && route.app.constraints.include?(constraint)
  end

  def site_routes_without_constraint(route_set)
    route_set.routes.reject { |route| under_prefix?(route) || HOST_FREE.include?(PUBLIC[key(route)]) }
      .reject { |route| constrained_by?(route, HostRouteConstraint::Site) }.map { |route| key(route) }
  end

  def key(route)
    "#{route.verb} #{route.path.spec}"
  end

  # Journey writes an optional format group straight after the segment.
  def under_prefix?(route)
    spec = route.path.spec.to_s
    prefix = "/#{ContentSpiel::ADMIN_PATH}"
    spec == prefix || spec.start_with?("#{prefix}/", "#{prefix}(")
  end

  def outside(route_set)
    route_set.routes.reject { |route| under_prefix?(route) || PUBLIC.key?(key(route)) }.map { |route| key(route) }
  end
end
