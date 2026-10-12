require "test_helper"

# What is wrong with a theme folder (theming spec §8, decision 14). The
# folder is checked strictly: a file the contract does not name stops the
# boot, because the alternative is a misspelt template that is silently
# never used. So does a template that cannot draw a page (a frame with no
# page in it, a title pattern that prints nothing) and one that writes what
# is the CMS's to write in <head>.
class Theme::CheckTest < ActiveSupport::TestCase
  FRAME = "views/layouts/public/_frame.html.erb".freeze
  TITLE = "views/layouts/public/_title.html.erb".freeze
  HEAD = "views/layouts/public/_head.html.erb".freeze

  # The files are a Hash of path => content, in braces or bare. Bare, Ruby
  # hands a Hash written beside a keyword as keywords, so they are taken
  # here as `**bare` (a path is a String key, which `**` accepts).
  def problems_with(files = nil, deep: false, **bare)
    files ||= bare
    with_theme_copy do |dir|
      files.each do |relative, content|
        dir.join(relative).dirname.mkpath
        dir.join(relative).write(content)
      end
      return Theme::Check.problems(ThemeFolder.new(dir), deep: deep)
    end
  end

  test "the second theme has no problem, checked deeply too, and neither has the default theme" do
    folder = ThemeFolder.new(ThemeTestHelper::PLAIN)

    assert_empty Theme::Check.problems(folder)
    assert_empty Theme::Check.problems(folder, deep: true)
    assert_empty Theme::Check.problems(ThemeFolder.new(nil), deep: true)
  end

  # What `bin/rails theme:new` will hand a person is a copy of these, so the
  # check must not refuse the CMS's own templates.
  test "a folder of every default template the contract names has no problem, checked deeply too" do
    Dir.mktmpdir("theme") do |dir|
      copies = Theme::Contract::TEMPLATES.keys.map { |path| [ "app/views/#{path}", "views/#{path}" ] } +
        Theme::Contract::COMPONENTS.keys.map { |path| [ "app/components/#{path}.html.erb", "components/#{path}.html.erb" ] }
      copies.each do |from, to|
        FileUtils.mkdir_p(File.dirname(File.join(dir, to)))
        FileUtils.cp(Rails.root.join(from), File.join(dir, to))
      end

      assert_empty Theme::Check.problems(ThemeFolder.new(dir), deep: true)
    end
  end

  test "a file the contract does not name is refused by name: a misspelt template, a backup file, a layout" do
    {
      "views/pages/shwo.html.erb" => "a misspelt template",
      "views/pages/show.html.erb~" => "an editor's backup",
      "views/layouts/application.html.erb" => "the layout",
      "views/pages/_seo_meta.html.erb" => "the CMS's head tags",
      "views/shared/_theme_head.html.erb" => "the light/dark script",
      "views/layouts/public/_preview_banner.html.erb" => "the preview bar",
      "views/layouts/admin.html.erb" => "CS Studio's layout",
      "views/admin/dashboard/show.html.erb" => "a CS Studio view",
      "components/media/picture_component.html.erb" => "a component that is called, not replaced",
      "components/rich_text/image_component.html.erb" => "rich text's own component",
      "components/blocks/image_component.rb" => "Ruby",
      "components/blocks/image_component.html.haml" => "another template language",
      "assets/stylesheets/other.css" => "a second stylesheet",
      "assets/theme.css" => "a stylesheet in the wrong place",
      "javascript/application.js" => "a script that is no controller",
      "javascript/controllers/helpers.js" => "a module that is no controller"
    }.each do |file, what|
      problems = problems_with(file => "x")

      assert_equal 1, problems.size, "#{what} (#{file}): #{problems.inspect}"
      assert_includes problems.first, file
      assert_includes problems.first, "not part of the theme contract"
      assert_includes problems.first, "Rename it to a name the contract has, or take it out of the folder."
    end
  end

  test "a file with no place in a theme is one problem, whatever it holds and whatever it is named like" do
    problems = problems_with({ "views/layouts/application.html.erb" => "<%= csp_meta_tag %><%= csrf_meta_tags %>\n<% if params[:q] %>" }, deep: true)

    assert_equal 1, problems.size, problems.inspect
    assert_includes problems.first, "not part of the theme contract"
  end

  test "what a theme may bring is let through: its own partials at any depth, images, fonts, controllers in folders" do
    assert_empty problems_with(
      "views/theme/_note.html.erb" => "x", "views/theme/parts/_deep.html.erb" => "x",
      "assets/images/icons/arrow.svg" => "x", "assets/fonts/site-sans.woff2" => "x",
      "javascript/controllers/docs/copy_controller.js" => "x", "views/pages/.DS_Store" => "x"
    )
  end

  # A dot file is an operating system's or an editor's and is passed over
  # (`.DS_Store`, `.keep`), which leaves it out of the check and of the
  # fingerprint. One that is a template is still on the view path, where a
  # render that names it would find it: so it is refused, by its name.
  test "a hidden file that is a template is refused: it would be unchecked, outside the fingerprint and still there to render" do
    %w[views/theme/.x.html.erb views/pages/.show.html.erb components/blocks/.rich_text_component.html.erb].each do |file|
      problems = problems_with(file => "<%= params[:q] %>")

      assert_equal 1, problems.size, file
      assert_equal "#{file} is a hidden file and a template: it is left out of the check and of the theme's fingerprint, and a " \
                   "render that names it would still find it. Rename it without the dot, or take it out of the folder.", problems.first
    end

    assert_empty problems_with("views/pages/.DS_Store" => "x", "views/theme/.keep" => "", "assets/images/.thumbs.erb" => "x", ".editor.erb" => "x")
  end

  test "an asset named like one of the CMS's own is refused: a font, and a controller" do
    font = problems_with("assets/fonts/archivo-latin-400-normal.woff2" => "x")
    assert_equal 1, font.size
    assert_includes font.first, "assets/fonts/archivo-latin-400-normal.woff2"
    assert_includes font.first, "app/assets/fonts/archivo-latin-400-normal.woff2"
    assert_includes font.first, "Give it a name of its own."

    controller = problems_with("javascript/controllers/theme_controller.js" => "x")
    assert_equal 1, controller.size
    assert_includes controller.first, "app/javascript/controllers/theme_controller.js"
  end

  # A folder on the asset load path is published whole, so each takes its
  # own kind of file and nothing else: what is refused one folder over
  # ("a second stylesheet", "a script that is no controller") is refused
  # here too, and "a theme holds no Ruby" is true of every folder.
  test "the image and font folders take images and fonts by their extension, and nothing else" do
    %w[assets/images/helper.rb assets/images/x.erb assets/images/other.css assets/images/application2.js assets/images/page.html
       assets/images/notes.txt assets/images/site.woff2 assets/images/noextension
       assets/fonts/helper.rb assets/fonts/x.html.erb assets/fonts/fonts.css assets/fonts/loader.js assets/fonts/mark.svg
       assets/fonts/licence.txt].each do |file|
      problems = problems_with(file => "x")

      assert_equal 1, problems.size, "#{file}: #{problems.inspect}"
      assert_includes problems.first, "#{file} is not part of the theme contract"
      assert_includes problems.first, "images/ (png, jpg, jpeg, gif, svg, webp, avif, ico) and fonts/ (woff2, woff, ttf, otf)"
    end

    assert_empty problems_with(
      "assets/images/a.png" => "x", "assets/images/b.jpg" => "x", "assets/images/c.jpeg" => "x", "assets/images/d.gif" => "x",
      "assets/images/e.svg" => "x", "assets/images/f.webp" => "x", "assets/images/g.avif" => "x", "assets/images/h.ico" => "x",
      "assets/images/deep/SHOUT.PNG" => "x",
      "assets/fonts/a.woff2" => "x", "assets/fonts/b.woff" => "x", "assets/fonts/c.ttf" => "x", "assets/fonts/d.otf" => "x"
    )
  end

  test "an asset named like one of a gem's scripts or like a file of the CMS's stylesheets folder is refused" do
    gems = Theme::Check.cms_asset_roots(Rails.root).map(&:last).reject { |path| path.to_s.start_with?("#{Rails.root}/") }
    assert_operator gems.size, :>=, 3, "the gems' asset folders are asked"
    assert gems.any? { |path| path.join("turbo.min.js").file? }, "Turbo's script is in one of them"

    # Nothing a theme may hold can be named like those today (a script is
    # served as controllers/…_controller.js), so the roots are shown with a
    # load path of one invented folder.
    Dir.mktmpdir("gem") do |gem|
      FileUtils.mkdir_p(File.join(gem, "controllers"))
      File.write(File.join(gem, "controllers/hello_controller.js"), "x")
      roots = Theme::Check.cms_asset_roots(Rails.root, paths: [ gem, Rails.root.join("test/fixtures/themes/plain/javascript").to_s ])

      assert_equal Theme::Check::CMS_ASSET_ROOTS + [ gem ], roots.map(&:first), "a root inside the application is the list's, not the load path's"
    end
  end

  # The list must be whole, and must not say one thing before a build and
  # another after it.
  test "every root of the asset load path is one the check asks, or is named here with its reason" do
    known = Theme::Check.cms_asset_roots(Rails.root).map { |_, path| path.to_s }
    reasons = {
      Rails.root.join(Theme::Check::BUILDS).to_s => "built files: there or not by whether a build has run, and no name a theme may bring",
      ThemeTestHelper::PLAIN.join("assets/images").to_s => "the second theme's, on the path in the test environment only",
      ThemeTestHelper::PLAIN.join("javascript").to_s => "the second theme's, on the path in the test environment only"
    }

    unknown = Rails.application.config.assets.paths.map(&:to_s) - known - reasons.keys
    assert_empty unknown, "a root of the asset load path that Theme::Check does not ask: add it to CMS_ASSET_ROOTS"
    assert_not_includes Theme::Check::CMS_ASSET_ROOTS, Theme::Check::BUILDS
    Theme::Check::CMS_ASSET_ROOTS.each { |relative| assert Rails.root.join(relative).directory?, "#{relative} is gone" }
  end

  # THE CASE EVERY REAL SITE IS: the theme is a folder outside the
  # application, and the initializer has put its own asset folders on the
  # load path before the check runs (config/initializers/theme.rb). Those
  # are the theme's, not a gem's: asked as "the CMS's own", each of the
  # theme's assets is found in the theme's own folder and the site does not
  # start. (Shipped once: every theme the suite booted was the fixture,
  # inside the application, which another rule let through.)
  test "a theme outside the application whose own asset folders are on the load path shadows nothing: an image, a font, a controller" do
    with_theme_copy do |dir|
      assert_not dir.to_s.start_with?("#{Rails.root}/"), "the copy is outside the application"
      dir.join("assets/fonts").mkpath
      dir.join("assets/fonts/plain-sans.woff2").write("x")
      folder = ThemeFolder.new(dir)
      assert_equal %w[assets/images assets/fonts javascript].map { |name| dir.join(name) }, folder.asset_paths
      paths = Rails.application.config.assets.paths + folder.asset_paths.map(&:to_s)

      assert_empty Theme::Check.problems(folder, deep: true, paths: paths)
      assert_empty Theme::Check.problems(folder, paths: paths.map { |path| File.realpath(path) rescue path }), "the same folders by their real path"

      # A second copy, checked while the first is the theme the application
      # started with (`bin/rails theme:check` of a folder beside the running
      # one): the first one's folders are on the path and are a theme's too.
      with_theme_copy do |other|
        assert_empty Theme::Check.problems(ThemeFolder.new(other), paths: paths, started: folder)
        assert_equal 2, Theme::Check.problems(ThemeFolder.new(other), paths: paths, started: ThemeFolder.new(nil)).size,
          "without knowing which theme started, the running theme's folders would be taken for a gem's"
      end

      # And what is the CMS's or a gem's is still refused beside them.
      dir.join("javascript/controllers/theme_controller.js").write("x")
      dir.join("javascript/stimulus.min.js").write("x")
      problems = Theme::Check.problems(ThemeFolder.new(dir), paths: paths)
      assert_equal 1, problems.grep(%r{javascript/controllers/theme_controller\.js is named like an asset of the CMS's own \(app/javascript/}).size
      assert_empty problems.grep(/#{Regexp.escape(dir.to_s)}/), "no problem names the theme's own folder as the CMS's"
    end
  end

  test "what the check says of an asset does not depend on whether a build has run" do
    Dir.mktmpdir("application") do |root|
      FileUtils.mkdir_p(File.join(root, "app/assets/builds"))
      FileUtils.mkdir_p(File.join(root, "app/assets/images"))
      File.write(File.join(root, "app/assets/images/logo.svg"), "x")
      folder = lambda do |&block|
        with_theme_copy do |dir|
          dir.join("assets/images/logo.svg").write("x")
          dir.join("assets/images/theme.svg").write("x")
          block.call(Theme::Check.problems(ThemeFolder.new(dir), root: root))
        end
      end

      before = folder.call { |problems| problems }
      File.write(File.join(root, "app/assets/builds/theme.svg"), "built")
      File.write(File.join(root, "app/assets/builds/theme.css"), "built")
      after = folder.call { |problems| problems }

      assert_equal 1, before.size
      assert_includes before.first, "assets/images/logo.svg is named like an asset of the CMS's own (app/assets/images/logo.svg)"
      assert_equal before, after
    end
  end

  test "a frame that never yields the page is refused, and says what to add" do
    [ "<div class=\"frame\"><%= render \"layouts/public/header\" %></div>\n", "<main><%# <%= yield %> %></main>\n", "<main><% yield %></main>\n",
      "<main><%= yield :sidebar %></main>\n" ].each do |frame|
      problems = problems_with(FRAME => frame)

      assert_equal 1, problems.size, frame
      assert_includes problems.first, "#{FRAME} never prints the page"
      assert_includes problems.first, "Add <%= yield %> where the page goes."
    end
    assert_empty problems_with(FRAME => "<main>\n  <%=   yield -%>\n</main>\n")
    assert_empty problems_with(FRAME => "<main><%= yield%></main>")
  end

  test "a frame that prints the page another way is a frame: handed to a tag, to a partial, printed raw" do
    [ "<%= tag.main yield %>", "<%= tag.main(yield, class: \"x\") %>", "<%= content_tag :main, yield %>", "<main><%== yield %></main>",
      "<%= render \"theme/body\", content: yield %>", "<%= yield :sidebar %><main><%= yield %></main>" ].each do |frame|
      assert_empty problems_with(FRAME => "#{frame}\n", "views/theme/_body.html.erb" => "<%= content %>"), frame
    end
  end

  test "a title pattern that prints nothing is refused: empty, a comment alone, code that prints nothing" do
    [ "", "  \n", "<%# the title %>\n", "<% title = site_title %>\n" ].each do |pattern|
      problems = problems_with(TITLE => pattern)

      assert_equal 1, problems.size, pattern.inspect
      assert_includes problems.first, "#{TITLE} prints nothing"
      assert_includes problems.first, "or delete the file to get the default pattern"
    end
    assert_empty problems_with(TITLE => "<%= site_title %>\n")
    assert_empty problems_with(TITLE => "Always this")
  end

  test "a template that prints one of the CMS's own head tags is refused, by its file and by the tag" do
    {
      %(<link rel="canonical" href="https://elsewhere.example/">) => "a canonical link",
      %(<%= tag.link rel: "canonical", href: "/" %>) => "a canonical link",
      %(<%= tag.link(rel: :canonical, href: "/") %>) => "a canonical link",
      %(<link rel="alternate" hreflang="de" href="/de">) => "a language link (rel=\"alternate\" with hreflang)",
      %(<link hreflang="x-default" href="/" rel="alternate">) => "a language link (rel=\"alternate\" with hreflang)",
      %(<%= tag.link rel: "alternate", hreflang: code, href: url %>) => "a language link (rel=\"alternate\" with hreflang)",
      %(<link rel="alternate" href="<%= url %>" hreflang="<%= code %>">) => "a language link (rel=\"alternate\" with hreflang)",
      %(<%= tag(:link, :rel => "alternate", :hreflang => code) %>) => "a language link (rel=\"alternate\" with hreflang)",
      %(<%= tag.link :rel => "canonical", :href => "/" %>) => "a canonical link",
      %(<%= tag.link "rel" => "canonical", "href" => "/" %>) => "a canonical link",
      %(<%= tag.script type: :importmap %>) => "the import map",
      %(<link rel="alternate stylesheet" href="/other.css">) => "a stylesheet link",
      %(<meta property="og:url" content="https://elsewhere.example/">) => "the og:url tag",
      %(<%= tag.meta property: "og:url", content: "/" %>) => "the og:url tag",
      %(<%= csp_meta_tag %>) => "the content security policy's tag",
      %(<meta http-equiv="Content-Security-Policy" content="default-src *">) => "the content security policy's tag",
      %(<meta name="csp-nonce" content="x">) => "the content security policy's tag",
      %(<%= javascript_importmap_tags %>) => "the import map",
      %(<script type="importmap">{}</script>) => "the import map",
      %(<%= stylesheet_link_tag "theme" %>) => "a stylesheet link",
      %(<link rel="stylesheet" href="/other.css">) => "a stylesheet link"
    }.each do |markup, tag|
      problems = problems_with(HEAD => "<meta name=\"theme-color\" content=\"x\">\n#{markup}\n")

      assert_equal 1, problems.size, "#{markup}: #{problems.inspect}"
      assert_includes problems.first, "#{HEAD} prints #{tag}"
      assert_includes problems.first, "Delete it from the template."
    end
  end

  test "a CMS head tag is refused in any template of the theme, not in the head partial alone" do
    %w[views/layouts/public/_icons.html.erb views/layouts/public/_frame.html.erb views/pages/show.html.erb views/theme/_seo.html.erb
       components/blocks/rich_text_component.html.erb].each do |file|
      problems = problems_with(file => "<%= yield %>\n<link rel=\"canonical\" href=\"/\">\n")

      assert_equal [ file ], problems.map { |problem| problem.split(" ").first }
      assert_includes problems.first, "prints a canonical link"
    end
  end

  test "a template that asks for the CSRF token is refused, and the message says why a public page has none" do
    [ "<%= csrf_meta_tags %>", "<%= csrf_meta_tag %>", %(<meta name="csrf-token" content="<%= form_authenticity_token %>">) ].each do |markup|
      problems = problems_with(HEAD => "#{markup}\n")

      assert_equal 1, problems.size, "#{markup}: #{problems.inspect}"
      assert_includes problems.first, "#{HEAD} asks for the CSRF token"
      assert_includes problems.first, "a cookie"
      assert_includes problems.first, "Delete it from the template."
    end
  end

  test "a template that writes to the head's slot is refused and pointed at the head partial" do
    [ "<% content_for :head do %><meta name=\"x\"><% end %>", "<% content_for(:head, tag.meta(name: \"x\")) %>",
      "<% content_for \"head\" do %>x<% end %>", "<% provide :head, \"x\" %>" ].each do |markup|
      problems = problems_with("views/pages/show.html.erb" => "#{markup}\n<h1>x</h1>\n")

      assert_equal 1, problems.size, "#{markup}: #{problems.inspect}"
      assert_includes problems.first, "views/pages/show.html.erb writes to the head's slot (content_for :head)"
      assert_includes problems.first, "Put the tag into #{HEAD}"
    end
  end

  test "the reading is not fooled: a comment, a word in text, a language link in the page, a feed link, another slot" do
    assert_empty problems_with(
      HEAD => "<%# no canonical link, no csrf_meta_tags and no content_for :head here %>\n" \
              "<link rel=\"alternate\" type=\"application/rss+xml\" href=\"/feed\">\n<link rel=\"preload\" href=\"x.woff2\" as=\"font\">\n",
      "views/layouts/public/_language_switcher.html.erb" =>
        "<%= link_to \"de\", \"/de\", hreflang: \"de\", rel: \"alternate\" %>\n" \
        "<a rel=\"alternate\" hreflang=\"<%= code %>\" href=\"<%= path %>\">de</a>\n" \
        "<a href=\"/es\" hreflang=\"es\" rel=\"alternate\">es</a>\n",
      "views/pages/show.html.erb" => "<p>The canonical text, in a stylesheet of words. A form_with a session, @page = it.</p>\n" \
                                     "<% content_for :sidebar do %>x<% end %>\n<% if content_for?(:sidebar) %><% end %>\n" \
                                     "<%= @page %><%= translated(@page, :title) %>\n<% if @post == nil || @page != @post %><% end %>\n" \
                                     "<%= render \"theme/crumb\", page: @page, data: { at: @page.id >= 1 } %>\n"
    )
  end

  # The layout is rendered after the page template, in the same view, and
  # reads @page, @post and @preview_record for the title and the head.
  test "a template that assigns an instance variable is refused, however it is written" do
    [ "<% @post = nil %>", "<% @page = Page.first %>", "<% @preview_record ||= @page %>", "<% @count += 1 %>",
      "<% instance_variable_set(:@page, nil) %>", "<%= (@title = \"x\") %>", "<% @a, b = 1, 2 %><% @page =\n  nil %>" ].each do |markup|
      problems = problems_with("views/theme/_x.html.erb" => "#{markup}\n")

      assert_equal 1, problems.size, "#{markup}: #{problems.inspect}"
      assert_includes problems.first, "views/theme/_x.html.erb assigns an instance variable"
      assert_includes problems.first, "Use a local variable"
    end
  end

  test "a form that is sent with a token is refused, and a GET form and a plain form tag are not" do
    [ "<%= form_with url: \"/newsletter\" do |form| %><% end %>", "<%= form_with(url: \"/x\", method: :post) { } %>",
      "<%= form_tag \"/x\" do %><% end %>", "<%= button_to \"Vote\", \"/vote\" %>", "<%= form_for @page do |form| %><% end %>" ].each do |markup|
      problems = problems_with("views/theme/_x.html.erb" => "#{markup}\n")

      assert_equal 1, problems.size, "#{markup}: #{problems.inspect}"
      assert_includes problems.first, "views/theme/_x.html.erb has a form that is sent with a CSRF token"
      assert_includes problems.first, "Write a search form with `method: :get`"
    end

    assert_empty problems_with("views/theme/_search.html.erb" =>
      "<%= form_with url: \"/search\", method: :get do |form| %><%= form.search_field :q %><% end %>\n" \
      "<%= form_tag \"/search\", method: \"get\" do %><% end %>\n<%= button_to \"Go\", \"/search\", :method => :get %>\n" \
      "<form action=\"https://lists.example.org/join\" method=\"post\"><input name=\"email\"></form>\n" \
      "<p>A form_with nothing in it.</p>\n")
  end

  test "the deep check names a template that does not compile, with its line" do
    problems = problems_with({ "views/theme/_broken.html.erb" => "<p>fine</p>\n<% if true %>\n<p>never closed</p>\n" }, deep: true)

    assert_equal 1, problems.size
    assert_includes problems.first, "views/theme/_broken.html.erb"
    assert_includes problems.first, "does not compile"
    assert_empty problems_with("views/theme/_broken.html.erb" => "<% if true %>"), "syntax is the deep check's, not the boot's"
  end

  test "the deep check refuses a template that reads the request, the parameters, the cookies, the session or the flash" do
    %w[params request cookies session flash].each do |name|
      problems = problems_with({ "views/theme/_x.html.erb" => "<p><%= #{name}[:q] %></p>\n" }, deep: true)

      assert_equal 1, problems.size, name
      assert_includes problems.first, "views/theme/_x.html.erb reads #{name}"
      assert_includes problems.first, "no sandbox"
    end
  end

  test "the deep check sees the name asked of the view, the controller and the helpers, and in a ternary" do
    {
      "<%= helpers.request.path %>" => "request", "<%= helpers.params[:q] %>" => "params", "<%= controller.params[:q] %>" => "params",
      "<%= controller.session[:x] %>" => "session", "<%= self.cookies[:x] %>" => "cookies", "<%= signed ? params : nil %>" => "params",
      "<%= signed ? nil : request %>" => "request", "<% flash.each { } %>" => "flash", "<%= helpers.flash[:notice] %>" => "flash"
    }.each do |markup, name|
      problems = problems_with({ "views/theme/_x.html.erb" => "#{markup}\n" }, deep: true)

      assert_equal 1, problems.size, "#{markup}: #{problems.inspect}"
      assert_includes problems.first, "views/theme/_x.html.erb reads #{name}"
    end
  end

  test "the deep check is not fooled by the words in text, in a comment, as a method of something else or as a key" do
    assert_empty problems_with({ "views/theme/_x.html.erb" => <<~ERB }, deep: true)
      <p>Send a request, we keep no cookies and no session.</p>
      <%# params and request are not read here %>
      <%= link_to "x", "/x", data: { session: "1", request: "2" } %>
      <%= translated(theme_site, :title).to_s.then { |text| text.request_id rescue text } %>
      <%= link_to "y", "/y", data: { params: "1", cookies: "2", flash: "3" }, class: post.session ? "a" : "b" %>
    ERB
  end

  test "load refuses a folder with a problem, names the variable, the folder and the file, and loads a sound one" do
    with_theme_copy do |dir|
      assert_instance_of Theme, Theme.load(ThemeFolder.new(dir))

      dir.join("views/pages/shwo.html.erb").write("x")
      dir.join(HEAD).write("<%= csrf_meta_tags %>")
      error = assert_raises(ThemeFolder::Invalid) { Theme.load(ThemeFolder.new(dir)) }

      assert_includes error.message, "THEME_PATH"
      assert_includes error.message, dir.to_s
      assert_includes error.message, "views/pages/shwo.html.erb"
      assert_includes error.message, "#{HEAD} asks for the CSRF token"
      assert_includes error.message, "Correct the folder, or unset THEME_PATH to start with the default theme."
    end
  end

  test "an empty folder is a theme with no problem, and loads" do
    Dir.mktmpdir("theme") do |dir|
      assert_empty Theme::Check.problems(ThemeFolder.new(dir), deep: true)
      assert_equal 0, Theme.load(ThemeFolder.new(dir)).template_count
    end
  end
end
