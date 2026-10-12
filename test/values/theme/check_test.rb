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

  test "two files of the theme that would be served under one name are refused" do
    problems = problems_with("assets/images/mark.woff2" => "x", "assets/fonts/mark.woff2" => "y")

    assert_equal 1, problems.size
    assert_includes problems.first, "assets/fonts/mark.woff2"
    assert_includes problems.first, "assets/images/mark.woff2"
    assert_includes problems.first, "Rename one of them."
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
      %(<meta property="og:url" content="https://elsewhere.example/">) => "the og:url tag",
      %(<%= tag.meta property: "og:url", content: "/" %>) => "the og:url tag",
      %(<%= csp_meta_tag %>) => "the content security policy's tag",
      %(<meta http-equiv="Content-Security-Policy" content="default-src *">) => "the content security policy's tag",
      %(<meta name="csp-nonce" content="x">) => "the content security policy's tag",
      %(<%= javascript_importmap_tags %>) => "the import map",
      %(<script type="importmap">{}</script>) => "the import map",
      %(<%= stylesheet_link_tag "theme-default" %>) => "a stylesheet link",
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
      "views/layouts/public/_language_switcher.html.erb" => "<%= link_to \"de\", \"/de\", hreflang: \"de\", rel: \"nofollow\" %>\n",
      "views/pages/show.html.erb" => "<p>The canonical text, in a stylesheet of words.</p>\n<% content_for :sidebar do %>x<% end %>\n" \
                                     "<% if content_for?(:sidebar) %><% end %>\n"
    )
  end

  test "the deep check names a template that does not compile, with its line" do
    problems = problems_with({ "views/theme/_broken.html.erb" => "<p>fine</p>\n<% if true %>\n<p>never closed</p>\n" }, deep: true)

    assert_equal 1, problems.size
    assert_includes problems.first, "views/theme/_broken.html.erb"
    assert_includes problems.first, "does not compile"
    assert_empty problems_with("views/theme/_broken.html.erb" => "<% if true %>"), "syntax is the deep check's, not the boot's"
  end

  test "the deep check refuses a template that reads the request, the parameters, the cookies or the session" do
    %w[params request cookies session].each do |name|
      problems = problems_with({ "views/theme/_x.html.erb" => "<p><%= #{name}[:q] %></p>\n" }, deep: true)

      assert_equal 1, problems.size, name
      assert_includes problems.first, "views/theme/_x.html.erb reads #{name}"
    end
  end

  test "the deep check is not fooled by the words in text, in a comment, as a method of something else or as a key" do
    assert_empty problems_with({ "views/theme/_x.html.erb" => <<~ERB }, deep: true)
      <p>Send a request, we keep no cookies and no session.</p>
      <%# params and request are not read here %>
      <%= link_to "x", "/x", data: { session: "1", request: "2" } %>
      <%= translated(theme_site, :title).to_s.then { |text| text.request_id rescue text } %>
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
