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
  ADMIN_ONLY = %w[controllers/admin/ rich_text/ saving/ live/ notes/ editing/ search/ i18n/ media/ mind_graph/ @tiptap prosemirror linkifyjs sortablejs d3-force].freeze

  test "a public page loads the application entry point without any admin module" do
    create_page(title: "About")

    get "/"

    assert_response :success
    preloads = modulepreloads
    assert preloads.any? { |href| href.include?("application") }, "expected the application entry point to be preloaded"
    ADMIN_ONLY.each do |name|
      assert preloads.none? { |href| href.include?(name) }, "#{name} is modulepreloaded on a public page: #{preloads.grep(/#{Regexp.escape(name)}/).inspect}"
    end
    assert_includes entry_point_script, %(import "site")
    assert_not_includes entry_point_script, %(import "admin")
    assert preloads.none? { |href| href.include?("controllers/admin/") }
  end

  # Theming spec §4, "Scripts": a theme's controllers are registered by the
  # `site` entry point, which the public layout alone loads. CS Studio and
  # sign-in load `admin` and `application`, and `controllers/index.js`
  # registers neither CS Studio's controllers nor a theme's by itself.
  test "only the public layout loads the site entry point, and with it the theme's controllers" do
    create_page(title: "About")
    get "/"
    assert modulepreloads.any? { |href| href.include?("hello_controller") }, "the theme's controller is preloaded on a public page"

    get admin_sign_in_path
    assert_not_includes entry_point_script, %(import "site")
    assert modulepreloads.none? { |href| href.include?("hello_controller") }

    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
    get "/cs-studio"
    assert_includes entry_point_script, %(import "admin")
    assert_not_includes entry_point_script, %(import "site")
    assert modulepreloads.none? { |href| href.include?("hello_controller") }
  end

  test "the site's own registration leaves CS Studio's and a theme's controllers to their entry points" do
    index = Rails.root.join("app/javascript/controllers/index.js").read
    site = Rails.root.join("app/javascript/site.js").read

    assert_includes index, %(registerControllers((path) => !path.startsWith("controllers/admin/") && !path.startsWith("controllers/theme/")))
    assert_includes site, %(import "application")
    assert_includes site, %(registerControllers((path) => path.startsWith("controllers/theme/")))
  end

  test "CS Studio loads the admin entry point and preloads the editor stack" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
    post = create_post(title: "Notes")

    get "/cs-studio/posts/#{post.id}"

    assert_response :success
    preloads = modulepreloads
    # `live/connection` and `notes/merge` among them: pinned `preload: "admin"`,
    # they are part of what every CS Studio screen runs (the notes' two
    # controllers on <body> import them), not a late import.
    %w[admin @tiptap--core controllers/admin/rich_text/editor_controller rich_text/schema prosemirror-model live/connection live/state notes/merge].each do |name|
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
  # address, carries nothing that subscribes (`admin--notes--live` and
  # `admin--notes--inbox` are the controllers that listen, through
  # `live/connection`, the one script that asks turbo-rails for its consumer;
  # Turbo's own stream element is used nowhere) and preloads no script that
  # would. Each fragment below is one the next test finds on a CS Studio page.
  test "a public page asks for no cable connection" do
    create_page(title: "About")

    get "/"

    assert_response :success
    assert_select "meta[name=action-cable-url]", count: 0
    assert_select "[data-controller*='notes--live']", count: 0
    assert_select "[data-controller*='notes--inbox']", count: 0
    assert_select "[data-controller*='notes--alert']", count: 0
    assert_no_match "turbo-cable-stream-source", response.body
    assert modulepreloads.none? { |href| href.include?("notes/live_controller") }
    assert modulepreloads.none? { |href| href.include?("notes/inbox_controller") }
    # "notes/live" is in every specifier of the controller (`controllers/admin/notes/live_controller`),
    # so an inline import of it would contain it; modulepreload alone would not see an inline import.
    assert_not_includes entry_point_script, "notes/live"
    assert_not_includes entry_point_script, "notes/inbox"
    # Nor presence's part (`admin--presence--record`, in
    # `controllers/admin/presence/`), which subscribes for the record it is
    # on. Both fragments are found on an editor by the test below.
    assert_select "[data-controller*='presence--record']", count: 0
    assert modulepreloads.none? { |href| href.include?("controllers/admin/presence/") }
    assert_not_includes entry_point_script, "presence/record"
    # Nor the lists' (`admin--presence--list`, on the page tree and the posts
    # table), which listens for every list. Found on the Posts screen below.
    assert_select "[data-controller*='presence--list']", count: 0
    assert_select "[data-presence-marker]", count: 0
    assert_not_includes entry_point_script, "presence/list"
    # Nor the shared tooltip (`admin--ui--tooltip`), whose first users are
    # presence's people and markers; an admin page below carries it.
    assert_select "[data-controller~='admin--ui--tooltip']", count: 0
    assert modulepreloads.none? { |href| href.include?("controllers/admin/ui/tooltip_controller") }
    assert_not_includes entry_point_script, "ui/tooltip"
  end

  # The other half for the lists: the posts table and the page tree carry
  # the list's part, and its controller is preloaded.
  test "the posts list and the page tree in CS Studio carry presence's list and preload its controller" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
    post = create_post(title: "Notes")

    get "/cs-studio/posts"

    assert_response :success
    assert_select "[data-controller*='presence--list'][data-controller='admin--presence--list'] tr#post_#{post.id} [data-presence-marker='post-#{post.id}']"
    assert modulepreloads.any? { |href| href.include?("controllers/admin/presence/list_controller") }
    assert_select "tr#post_#{post.id} [data-presence-marker='post-#{post.id}'][data-controller~='admin--ui--tooltip']"
    assert modulepreloads.any? { |href| href.include?("controllers/admin/ui/tooltip_controller") }
    get "/cs-studio/pages/#{root_page.id}"
    assert_select "turbo-frame#tree[data-controller~='admin--presence--list'] [data-presence-marker='page-#{root_page.id}']"
    get "/cs-studio/tags"
    assert_select "[data-controller*='presence--list']", count: 0
  end

  # The other half for presence: an editor carries the part, in its header,
  # and its controller is preloaded like every admin controller.
  test "an editor in CS Studio carries presence's part and preloads its controller" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
    post = create_post(title: "Notes")

    get "/cs-studio/posts/#{post.id}"

    assert_response :success
    assert_select "header [data-controller*='presence--record'][data-controller='admin--presence--record'] turbo-frame#presence-post-#{post.id}"
    assert modulepreloads.any? { |href| href.include?("controllers/admin/presence/record_controller") }
    # A screen that shows no record has no such part.
    get "/cs-studio/tags"
    assert_select "[data-controller*='presence--record']", count: 0
  end

  # The other half: CS Studio does load them, on every screen, on <body>: the
  # record's side (`admin--notes--live`) and the person's (`admin--notes--inbox`,
  # with the addresses it fetches), and the one question the second asks the
  # first.
  test "CS Studio loads the notes' live controller on every screen" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))

    get "/cs-studio/tags"

    assert_response :success
    assert_select "body[data-controller~='admin--notes--live'][data-action~='visibilitychange@document->admin--notes--live#visible'][data-action~='admin--notes--inbox:watching@document->admin--notes--live#watched']"
    assert_select "body[data-controller~='admin--notes--inbox'][data-admin--notes--inbox-unread-url-value='/cs-studio/notes/unread'][data-admin--notes--inbox-delivery-url-value='/cs-studio/notes/deliveries/0'][data-admin--notes--inbox-person-value='#{users(:one).id}']"
    assert_select "template#toast-note-template", count: 1
    assert modulepreloads.any? { |href| href.include?("controllers/admin/notes/live_controller") }
    assert modulepreloads.any? { |href| href.include?("controllers/admin/notes/inbox_controller") }
    # And beside it what makes a mention heard (notes spec §6.4), with the
    # person's two settings as data.
    assert_select "body[data-controller~='admin--notes--alert'][data-action~='admin--notes--inbox:delivery@document->admin--notes--alert#delivery'][data-admin--notes--alert-sound-value=true][data-admin--notes--alert-desktop-value=false][data-admin--notes--alert-person-value='#{users(:one).id}']"
    assert modulepreloads.any? { |href| href.include?("controllers/admin/notes/alert_controller") }
  end

  # A theme brings controllers and nothing else to the import map: no pin
  # of its own, no third-party script, and no name outside
  # `controllers/theme/`, so none of its files can stand where a module of
  # the CMS's is looked up (Tiptap, the editor's modules, an admin
  # controller). The suite's map is config/importmap.rb plus the second
  # theme's pins (test/fixtures/themes/importmap.rb), drawn as a real
  # theme's are (`ThemeFolder#pins`); what the theme added is the difference.
  test "a theme adds pins under controllers/theme/ and nowhere else, and changes no pin of the CMS's" do
    names = Object.new
    def names.path_to_asset(path) = path
    imports = ->(map, key) { JSON.parse(map.to_json(resolver: names, cache_key: key))["imports"] }

    own = imports.(Importmap::Map.new.draw(Rails.root.join("config/importmap.rb")), :public_javascript_test_own)
    with_theme = imports.(Rails.application.importmap, :public_javascript_test_theme)

    assert_equal [ "controllers/theme/hello_controller" ], with_theme.keys - own.keys
    assert_equal own, with_theme.slice(*own.keys), "a pin of the CMS's own points elsewhere with the theme"
    assert_equal "controllers/hello_controller.js", with_theme["controllers/theme/hello_controller"]
  end

  # The other fence: which layout asks for which entry point is one word in
  # each layout, and `site` is in the public one alone.
  test "the site entry point is named by the public layout and by no other layout or view" do
    naming = Dir[Rails.root.join("app/{views,components,helpers}/**/*.{erb,rb}")].select do |file|
      File.read(file).match?(/javascript_importmap_tags\s*\(?\s*["']site["']/)
    end

    assert_equal [ "app/views/layouts/application.html.erb" ], naming.map { |file| Pathname(file).relative_path_from(Rails.root).to_s }
    every = Dir[Rails.root.join("app/views/layouts/*.html.erb")].select { |file| File.read(file).include?("javascript_importmap_tags") }
    assert_operator every.size, :>=, 3, "the public layout, CS Studio's and the product's each load an entry point"
  end

  # And inside the scripts: `site` is imported by a layout and by no script
  # of the CMS's, so neither CS Studio's entry point nor the one sign-in and
  # setup load can pull a theme's controllers in behind the layouts' backs.
  # (`admin` importing `site` would leave every layout test above green.)
  test "no script of the CMS's imports the site entry point or a theme's controller" do
    scripts = Dir[Rails.root.join("app/javascript/**/*.js")].to_h { |file| [ Pathname(file).relative_path_from(Rails.root).to_s, File.read(file) ] }
    assert_operator scripts.size, :>, 50
    code = scripts.transform_values { |text| text.gsub(%r{^\s*//.*$}, "") }

    importing = code.select { |_, text| text.match?(/\bimport\b[^\n]*["']site["']|\bimport\s*\(\s*["']site["']/) }.keys
    assert_empty importing, "imports the site entry point"
    naming = code.select { |_, text| text.include?("controllers/theme/") }.keys
    assert_equal %w[app/javascript/controllers/index.js app/javascript/site.js], naming.sort,
      "controllers/theme/ is named where the site's registration leaves it out and where `site` takes it in"
    assert_match(/\Aimport "application"\nimport \{ registerControllers \} from "controllers"\n\nregisterControllers\(\(path\) => path\.startsWith\("controllers\/admin\/"\)\)\n\z/,
      code.fetch("app/javascript/admin.js").lstrip, "CS Studio's entry point registers controllers/admin/ and nothing else")
  end

  # Code block spec §4: the copy button is a controller of the site's own,
  # at the top level of `controllers/` like `theme`, so a public page loads
  # it and still nothing of CS Studio.
  test "a public page with a Note block needs no script: it carries no controller of its own and no admin script" do
    page = create_page(title: "Guide")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "note", settings: { "kind" => "tip" } },
      translations: { "en" => { body: rich_doc("Words.") } }).ok?
    publish_changes(page)

    get PublicSite::Urls.new.path_for(page, "en")

    assert_select "aside.content-block--note-tip:not([data-controller])"
    ADMIN_ONLY.each do |name|
      assert modulepreloads.none? { |href| href.include?(name) }, "#{name} is modulepreloaded on a page with a Note block"
    end
  end

  test "a public page with a Code block carries the copy controller and no admin script" do
    page = create_page(title: "Docs")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "code", settings: { "code" => "a = 1" } }).ok?
    publish_changes(page)

    get PublicSite::Urls.new.path_for(page, "en")

    assert_response :success
    assert_select "figure[data-controller='code-copy'] button[hidden][data-action='code-copy#copy']"
    assert modulepreloads.any? { |href| href.include?("controllers/code_copy_controller") }, "the copy controller is preloaded with the site's own"
    ADMIN_ONLY.each do |name|
      assert modulepreloads.none? { |href| href.include?(name) }, "#{name} is modulepreloaded on a page with a Code block"
    end
    assert_select "[data-controller*='admin--']", count: 0
  end

  private

  def modulepreloads = css_select("link[rel=modulepreload]").map { |link| link["href"] }

  def entry_point_script = css_select("script[type=module]").map(&:text).join("\n")
end
