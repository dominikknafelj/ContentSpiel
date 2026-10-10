require "test_helper"

# Final fix wave (D, P12/P14): the public site and CS Studio load separate
# import-map entry points. A public page imports `application` -- Turbo and
# the site's own controllers only -- and modulepreloads nothing of CS
# Studio's: not its controllers (`controllers/admin/*`), not the editor's
# own modules (`rich_text/*`), not Tiptap/ProseMirror, SortableJS or D3
# (which no page preloads at all: only the mind graph's worker loads it).
# CS Studio's layout imports `admin`, which registers the admin controllers
# too, and modulepreloads the editor stack (`preload: "admin"` in
# config/importmap.rb) so the editor mounts without a waterfall of imports.
# The import map itself is the same on both (it's only a lookup table);
# what differs is what each page preloads and imports.
class PublicJavascriptTest < ActionDispatch::IntegrationTest
  ADMIN_ONLY = %w[controllers/admin/ rich_text/ saving/ live/ notes/ search/ i18n/ media/ mind_graph/ @tiptap prosemirror linkifyjs sortablejs d3-force].freeze

  test "a public page loads the application entry point without any admin module" do
    create_page(title: "About")

    get "/"

    assert_response :success
    preloads = modulepreloads
    assert preloads.any? { |href| href.include?("application") }, "expected the application entry point to be preloaded"
    ADMIN_ONLY.each do |name|
      assert preloads.none? { |href| href.include?(name) }, "#{name} is modulepreloaded on a public page: #{preloads.grep(/#{Regexp.escape(name)}/).inspect}"
    end
    assert_includes entry_point_script, %(import "application")
    assert_not_includes entry_point_script, %(import "admin")
  end

  test "CS Studio loads the admin entry point and preloads the editor stack" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
    post = create_post(title: "Notes")

    get "/cs-studio/posts/#{post.id}"

    assert_response :success
    preloads = modulepreloads
    %w[admin @tiptap--core controllers/admin/rich_text/editor_controller rich_text/schema prosemirror-model].each do |name|
      assert preloads.any? { |href| href.include?(name) }, "expected #{name} to be modulepreloaded in CS Studio: #{preloads.inspect}"
    end
    assert_includes entry_point_script, %(import "admin")
  end

  # Mind graph canvas spec §4.5: the graph's modules are imported by its own
  # controller with a dynamic `import()`, and d3-force only by the layout
  # worker, from its asset URL. So no page -- not even the Mind graph itself --
  # preloads either, and a screen that never draws a graph never fetches them.
  test "only the Mind graph loads its own modules, and no page preloads d3-force" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
    create_post(title: "Notes")

    [ "/cs-studio/tags", "/cs-studio/posts", "/cs-studio/mind_graph" ].each do |path|
      get path

      assert_response :success
      preloads = modulepreloads
      assert preloads.any? { |href| href.include?("controllers/admin/mind_graph/graph_controller") }, "the thin controller is an admin controller like any other"
      # The module folder app/javascript/mind_graph/ is the one that stays unloaded, whatever
      # prefix the assets are served under; the thin controller's own file lives in
      # controllers/admin/mind_graph/ and is preloaded like any admin controller. So the
      # test is "mind_graph/ with no admin/ before it": it matches /assets/mind_graph/app-x.js
      # and /any/prefix/mind_graph/layout_worker-x.js, and lets controllers/admin/mind_graph/ through.
      [ %r{(?<!admin/)mind_graph/}, /d3-force/ ].each do |pattern|
        assert preloads.none? { |href| href.match?(pattern) }, "#{pattern.inspect} is modulepreloaded on #{path}: #{preloads.grep(pattern).inspect}"
      end
      # Both are `preload: false`, so an inline `import "mind_graph/app"` in a layout would add no
      # modulepreload link and pass the lines above; the entry-point script is where it would show.
      assert_no_match(/(?<!admin\/)mind_graph\//, entry_point_script, "the entry-point script of #{path} imports the mind graph's modules")
      assert_not_includes entry_point_script, "d3-force"
    end

    # The Mind graph names the worker and d3-force as plain asset URLs, for the
    # script to start a worker from; no other screen mentions either.
    assert_select "[data-controller='admin--mind-graph--graph'][data-worker-url*='mind_graph/layout_worker'][data-d3-url*='d3-force']"
    get "/cs-studio/tags"
    assert_select "[data-worker-url], [data-d3-url]", count: 0
  end

  # Notes spec §6.2: the cable is CS Studio's. A public page names no cable
  # address, carries nothing that subscribes (`admin--notes--live` is the one
  # script that asks turbo-rails for its consumer, and Turbo's own stream
  # element is used nowhere) and preloads no script that would.
  test "a public page asks for no cable connection" do
    create_page(title: "About")

    get "/"

    assert_response :success
    assert_select "meta[name=action-cable-url]", count: 0
    assert_select "[data-controller*='notes--live']", count: 0
    assert_select "[data-controller*='notes--alert']", count: 0
    assert_no_match "turbo-cable-stream-source", response.body
    assert modulepreloads.none? { |href| href.include?("notes/live_controller") }
    # "notes/live" is in every specifier of the controller (`controllers/admin/notes/live_controller`),
    # so an inline import of it would contain it; modulepreload alone would not see an inline import.
    assert_not_includes entry_point_script, "notes/live"
  end

  # The other half: CS Studio does load it, on every screen, on <body>.
  test "CS Studio loads the notes' live controller on every screen" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))

    get "/cs-studio/tags"

    assert_response :success
    assert_select "body[data-controller~='admin--notes--live'][data-admin--notes--live-unread-url-value='/cs-studio/notes/unread'][data-admin--notes--live-delivery-url-value='/cs-studio/notes/deliveries/0'][data-action~='visibilitychange@document->admin--notes--live#visible']"
    assert_select "template#toast-note-template", count: 1
    assert modulepreloads.any? { |href| href.include?("controllers/admin/notes/live_controller") }
    # And beside it what makes a mention heard (notes spec §6.4), with the
    # person's two settings as data.
    assert_select "body[data-controller~='admin--notes--alert'][data-action~='admin--notes--live:delivery@document->admin--notes--alert#delivery'][data-admin--notes--alert-sound-value=true][data-admin--notes--alert-desktop-value=false][data-admin--notes--alert-person-value='#{users(:one).id}']"
    assert modulepreloads.any? { |href| href.include?("controllers/admin/notes/alert_controller") }
  end

  private

  def modulepreloads = css_select("link[rel=modulepreload]").map { |link| link["href"] }

  def entry_point_script = css_select("script[type=module]").map(&:text).join("\n")
end
