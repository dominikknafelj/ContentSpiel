require "test_helper"

# Final fix wave (D, P12/P14): the public site and CS Studio load separate
# import-map entry points. A public page imports `site` -- Turbo, the site's
# own controllers a public page draws and a theme's -- and modulepreloads
# nothing of sign-in's, setup's or CS
# Studio's: not its controllers (`controllers/admin/*`), not the editor's
# own modules (`rich_text/*`), not Tiptap/ProseMirror, SortableJS or D3
# (which no page preloads at all: only the mind graph's worker loads it).
# CS Studio's layout imports `admin`, which registers the admin controllers
# too, and modulepreloads the editor stack (`preload: "admin"` in
# config/importmap.rb) so the editor mounts without a waterfall of imports.
# The import map itself is the same on both (it's only a lookup table);
# what differs is what each page preloads and imports.
class PublicJavascriptTest < ActionDispatch::IntegrationTest
  ADMIN_ONLY = %w[controllers/admin/ rich_text/ saving/ live/ notes/ editing/ editor/ search/ i18n/ media/ mind_graph/ @tiptap prosemirror linkifyjs sortablejs d3-force].freeze

  test "a public page loads the site entry point without any admin module" do
    create_page(title: "About")

    get "/"

    assert_response :success
    preloads = modulepreloads
    assert preloads.any? { |href| href.include?("/site-") }, "expected the site entry point to be preloaded"
    assert_not_includes preloaded_modules, "application", "a public page does not load the application entry point"
    ADMIN_ONLY.each do |name|
      assert preloads.none? { |href| href.include?(name) }, "#{name} is modulepreloaded on a public page: #{preloads.grep(/#{Regexp.escape(name)}/).inspect}"
    end
    assert_includes entry_point_script, %(import "site")
    assert_not_includes entry_point_script, %(import "admin")
    assert preloads.none? { |href| href.include?("controllers/admin/") }
  end

  # A visitor's page preloads, of the site's own controllers, exactly `SITE`
  # (controllers/index.js), which `site.js` registers: not the sign-in,
  # password, invitation and setup controllers, which it never runs and
  # which competed with the theme's fonts on a phone. `site_controllers` in
  # config/importmap.rb is the Ruby side of that list.
  test "a public page preloads, of the site's own controllers, only the ones site.js registers" do
    create_page(title: "About")
    get "/"

    assert_equal site_set, preloaded_controllers - theme_controller_assets, "a public page preloads SITE, and no other controller of controllers/"
    assert_operator top_level_controllers.size, :>, site_set.size, "controllers/ holds more than the site's set"
    assert_includes site_set, "controllers/theme_controller"
    assert preloaded_modules.include?("controllers/index") && preloaded_modules.include?("controllers/application"), "the registration and Stimulus' application are preloaded"
  end

  # Everything a visitor's page names to fetch, held to an allow-list: the
  # `site` entry point and what it preloads, the theme's one stylesheet and
  # the icons (`/icon.*`, and `/apple-touch-icon.png`, `SiteIconsController`). Nothing of CS Studio's or of sign-in's, setup's, an
  # invitation's or the password reset's: not their entry points, not their
  # controllers, not `i18n/` (the strings `password_field` fetched when the
  # site's registration still imported it), not the product stylesheet
  # (`tailwind`) and no Action Cable address. The import map itself lists
  # every pin, which is one lookup table and fetches nothing; what the
  # scripts fetch when they run is test/system/public_resources_test.rb's.
  test "a public page names no resource but the site entry point's and the theme's, under both themes" do
    page = create_page(title: "About")
    [ :default, :plain ].each do |theme|
      run = -> do
        get "/"
        assert_response :success
        unexpected = named_resources.reject { |name| allowed_public_resource?(name) }
        assert_empty unexpected, "a public page under the #{theme} theme names a resource that is not the site's or the theme's"
        # The theme's one stylesheet: drawn in when it is small, which the
        # suite's default build is, and then named by no address at all
        # (`test/integration/public_stylesheet_test.rb` has the linked one).
        assert Theme::Stylesheet.current.inline?("automatic"), "the suite's built stylesheet is small enough to be drawn in"
        assert_empty css_select("link[rel=stylesheet]"), "a stylesheet drawn into the page is linked as well"
        assert_equal 1, css_select("head style[data-turbo-track=reload]").size, "the theme's one stylesheet"
        assert_select "meta[name=action-cable-url]", count: 0
      end
      theme == :plain ? with_plain_theme(&run) : run.call
    end
    assert page
  end

  # Sign-in, the password reset, an invitation and setup draw the product
  # and setup layouts, which load `application`: they preload every
  # controller of the site's own but the two only a visitor's page runs, so
  # theirs (password_field, reset_token, invitation_token, passkey_sign_in,
  # bot_check, mail_port) are there without a waterfall of imports. CS
  # Studio, through `admin`, too.
  test "sign-in, the password reset, an invitation and CS Studio preload their controllers" do
    own = top_level_controllers - public_only_set
    expect = ->(name, path, params = {}) do
      get path, params: params
      assert_response :success
      assert_includes entry_point_script, %(import "application"), name
      assert_equal own, preloaded_controllers, "#{name} preloads every controller of the site's own but PUBLIC_ONLY"
    end

    site_settings(:default).update!(setup_completed_at: Time.current)
    expect.("sign-in", admin_sign_in_path)
    expect.("the password reset", admin_edit_password_path)
    expect.("an invitation", "/#{ContentSpiel::ADMIN_PATH}/invitation", token: open_invitation("dana@example.com", name: "Dana").generate_token_for(:accept))

    sign_in_as(users(:one))
    get "/cs-studio"
    assert_includes entry_point_script, %(import "admin")
    assert_equal own, preloaded_controllers, "CS Studio preloads every controller of the site's own but PUBLIC_ONLY"
  end

  test "setup preloads its controllers" do
    start_fresh_install
    get setup_step_path("token")
    assert_response :success
    assert_includes entry_point_script, %(import "application")
    assert_equal top_level_controllers - public_only_set, preloaded_controllers
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

    application = Rails.root.join("app/javascript/application.js").read

    assert_not_includes index.gsub(%r{^\s*//.*$}, ""), "registerControllers((", "controllers/index.js registers nothing by itself: each entry point chooses"
    assert_includes application, %(registerControllers((path) => !path.startsWith("controllers/admin/") && !path.startsWith("controllers/theme/") && !PUBLIC_ONLY.includes(path)))
    assert_not_includes site, %(import "application")
    assert_includes site, %(registerControllers((path) => path.startsWith("controllers/theme/") || SITE.includes(path)))
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
    # The Table block's grid (`rich_text/table`, the table extension and
    # prosemirror-tables) is in the stack too: the one editor imports it, and
    # the public page above preloads none of it (`@tiptap`, `prosemirror`).
    %w[admin @tiptap--core controllers/admin/rich_text/editor_controller rich_text/schema rich_text/table @tiptap--extension-table @tiptap--pm--tables prosemirror-tables prosemirror-model live/connection live/state notes/merge editor/move_queue].each do |name|
      assert preloads.any? { |href| href.include?(name) }, "expected #{name} to be modulepreloaded in CS Studio: #{preloads.inspect}"
    end
    assert_includes entry_point_script, %(import "admin")
  end

  # SortableJS is imported with `import()` by the controllers that drag
  # (`editor/drag`'s `loadSortable`: the blocks list, the tree, Settings' language rows,
  # the Media screen's drag and the Gallery card's rows), and is
  # `preload: false`: a screen with nothing to drag never fetches it, though
  # the map still names it for the `import()` to resolve.
  test "a CS Studio screen with nothing to drag preloads no SortableJS, and the editor fetches it on demand" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
    page = create_page(title: "Landing")

    [ "/cs-studio", "/cs-studio/pages/#{page.id}" ].each do |path|
      get path

      assert_response :success
      assert modulepreloads.none? { |href| href.include?("sortablejs") }, "SortableJS is modulepreloaded on #{path}: #{modulepreloads.grep(/sortablejs/).inspect}"
      assert_not_includes entry_point_script, "sortablejs"
      assert_match(/"sortablejs":\s*"[^"]*sortablejs/, importmap_json, "the import map no longer maps sortablejs")
    end
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
    assert_equal %w[app/javascript/application.js app/javascript/site.js], naming.sort,
      "controllers/theme/ is named where the site's registration leaves it out and where `site` takes it in"
    assert_match(/\Aimport "application"\nimport \{ registerControllers \} from "controllers"\n\nregisterControllers\(\(path\) => path\.startsWith\("controllers\/admin\/"\)\)\n\z/,
      code.fetch("app/javascript/admin.js").lstrip, "CS Studio's entry point registers controllers/admin/ and nothing else")
  end

  # Code block spec §4: the copy button is a controller of the site's own,
  # at the top level of `controllers/` like `theme`, so a public page loads
  # it and still nothing of CS Studio.
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

  # The Form block's send in place is a controller of
  # the site's own, at the top level like `code-copy`; nothing of CS
  # Studio's editor reaches the page.
  test "a public page with a Form block carries the send controller and no admin script" do
    page = create_page(title: "Write")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "form", settings: { "form_id" => forms(:contact).id.to_s } }).ok?
    publish_changes(page)

    get PublicSite::Urls.new.path_for(page, "en")

    assert_response :success
    assert_select "form.content-block--form[data-controller='form-send'][data-action='form-send#send'][data-turbo=false]"
    assert modulepreloads.any? { |href| href.include?("controllers/form_send_controller") }, "the send controller is preloaded with the site's own"
    ADMIN_ONLY.each do |name|
      assert modulepreloads.none? { |href| href.include?(name) }, "#{name} is modulepreloaded on a page with a Form block"
    end
    assert_select "[data-controller*='admin--']", count: 0
  end

  # Search 2 spec §4.5: the suggestions' script is the site's own, at the
  # top level like `code-copy`, but a visitor's page alone runs it: `site`
  # registers it (`PUBLIC_ONLY` in `controllers/index.js`, which
  # `application`'s registration leaves out), and no CS Studio screen,
  # sign-in or setup imports or preloads it.
  test "search_suggest is registered by site.js and imported on no CS Studio screen" do
    page = create_page(title: "Help")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "search" }).ok?
    publish_changes(page)

    get PublicSite::Urls.new.path_for(page, "en")
    assert_response :success
    assert_select "form[role=search][data-controller='search-suggest'][data-search-suggest-url-value='/search/suggestions']"
    assert modulepreloads.any? { |href| href.include?("controllers/search_suggest_controller") }, "the suggestions' controller is preloaded on a public page"

    index = Rails.root.join("app/javascript/controllers/index.js").read
    assert_includes index, %("controllers/search_suggest_controller"), "PUBLIC_ONLY names it"
    assert_match(/export const PUBLIC_ONLY = \[[^\]]*"controllers\/search_suggest_controller"/m, index)

    assert_includes Rails.root.join("app/javascript/application.js").read, %(&& !PUBLIC_ONLY.includes(path)), "application's registration, which sign-in, setup and CS Studio run, leaves it out"
    assert_includes Rails.root.join("app/javascript/site.js").read, %(|| SITE.includes(path)), "the site entry point registers it"
    assert_match(/export const SITE = \[[^\]]*\.\.\.PUBLIC_ONLY/, index, "SITE holds PUBLIC_ONLY")

    get admin_sign_in_path
    assert_not_includes entry_point_script, "search_suggest"
    assert modulepreloads.none? { |href| href.include?("search_suggest") }, "sign-in does not preload it"
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
    [ "/cs-studio", "/cs-studio/pages/#{page.id}" ].each do |path|
      get path
      assert_response :success
      assert_not_includes entry_point_script, "search_suggest"
      assert_not_includes entry_point_script, %(import "site")
    end
    scripts = Dir[Rails.root.join("app/javascript/**/*.js")].reject { |file| file.end_with?("controllers/index.js", "search_suggest_controller.js") }
    assert_empty scripts.select { |file| File.read(file).include?("search_suggest") }, "no other script imports the suggestions' controller"
  end

  # Gallery block spec §7.5: the carousel's script is the site's own, at the
  # top level like `search-suggest`, and in `PUBLIC_ONLY`: a visitor's page
  # runs it, and no CS Studio screen, sign-in or setup imports it (CS
  # Studio's preview draws the public layout, which does).
  test "a public page with a carousel carries gallery-carousel and no admin script" do
    page = create_page(title: "Walks")
    assets = Array.new(2) { create_media_asset }
    page.content_blocks.create!(block_type: :gallery, position: 0, settings: { "layout" => "carousel", "images" => assets.map(&:id) })
    publish_changes(page)

    get PublicSite::Urls.new.path_for(page, "en")
    assert_response :success
    assert_select "section.content-block--gallery[data-controller='gallery-carousel']"
    assert modulepreloads.any? { |href| href.include?("controllers/gallery_carousel_controller") }, "the carousel's controller is preloaded on a public page"
    ADMIN_ONLY.each do |name|
      assert modulepreloads.none? { |href| href.include?(name) }, "#{name} is modulepreloaded on a page with a carousel"
    end

    index = Rails.root.join("app/javascript/controllers/index.js").read
    assert_match(/export const PUBLIC_ONLY = \[[^\]]*"controllers\/gallery_carousel_controller"/m, index, "PUBLIC_ONLY names it, so the site entry point alone registers it")

    get admin_sign_in_path
    assert_not_includes entry_point_script, "gallery_carousel"
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
    [ "/cs-studio", "/cs-studio/pages/#{page.id}" ].each do |path|
      get path
      assert_response :success
      assert_not_includes entry_point_script, "gallery_carousel"
    end
    scripts = Dir[Rails.root.join("app/javascript/**/*.js")].reject { |file| file.end_with?("controllers/index.js", "gallery_carousel_controller.js") }
    assert_empty scripts.select { |file| File.read(file).include?("gallery_carousel") }, "no other script imports the carousel's controller"
  end

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

  private

  def modulepreloads = css_select("link[rel=modulepreload]").map { |link| link["href"] }

  # Every address the page's head and body name to fetch: links but the
  # page's own canonical and language links, scripts with a source, and
  # images.
  def named_resources
    links = css_select("link[href]").reject { |link| %w[canonical alternate].include?(link["rel"]) }.map { |link| link["href"] }
    (links + css_select("script[src], img[src]").map { |node| node["src"] }).map { |href| asset_name(href) }.uniq
  end

  # A theme's controllers by their asset's name: pinned as
  # `controllers/theme/<name>`, served as `controllers/<name>.js` from the
  # theme's folder (`ThemeFolder#pins`).
  def theme_controller_assets
    JSON.parse(importmap_json).fetch("imports").select { |name, _| name.start_with?("controllers/theme/") }.values.map { |href| asset_name(href) }
  end

  # `/assets/controllers/theme_controller-1a2b.js` -> `controllers/theme_controller`.
  def asset_name(href) = URI(href).path.delete_prefix("/assets/").sub(/-\h+\.\w+\z/, "")

  # What the `site` entry point and a theme may name: Turbo, Stimulus, the
  # registration, SITE, a theme's controllers, the theme's stylesheet, and
  # an icon (the CMS's at the root, or a theme's from its assets).
  def allowed_public_resource?(name)
    %w[site @hotwired/turbo-rails turbo.min stimulus.min controllers/index controllers/application theme].include?(name) ||
      site_set.include?(name) || theme_controller_assets.include?(name) || name.match?(%r{\A/(icon\.(png|svg)|apple-touch-icon\.png)\z}) ||
      name.match?(/\A[\w-]+\z/) && !top_level_controllers.include?("controllers/#{name}") && Rails.root.glob("test/fixtures/themes/plain/assets/images/#{name}.*").any?
  end

  # The preloaded modules by name: an href is `/assets/<name>-<digest>.js`.
  def preloaded_modules = modulepreloads.map { |href| href.delete_prefix("/assets/").sub(/-\h+\.js\z/, "") }

  # The preloaded controllers of the site's own: those at the top of
  # app/javascript/controllers, not a theme's or CS Studio's.
  def preloaded_controllers = preloaded_modules.grep(%r{\Acontrollers/[a-z_]+_controller\z}).sort

  def top_level_controllers = Rails.root.glob("app/javascript/controllers/*_controller.js").map { |file| "controllers/#{file.basename(".js")}" }.sort

  # `SITE` and `PUBLIC_ONLY` as controllers/index.js writes them (`SITE`
  # spreads `PUBLIC_ONLY` into its own names).
  def site_set = (controller_list("SITE") + public_only_set).sort

  def public_only_set = controller_list("PUBLIC_ONLY")

  def controller_list(name)
    list = Rails.root.join("app/javascript/controllers/index.js").read[/^export const #{name} = \[([^\]]*)\]/, 1]
    assert list, "controllers/index.js exports #{name}"
    list.scan(/"(controllers\/[a-z_]+_controller)"/).flatten
  end

  def entry_point_script = css_select("script[type=module]").map(&:text).join("\n")

  def importmap_json = css_select("script[type=importmap]").map(&:text).join("\n")
end
