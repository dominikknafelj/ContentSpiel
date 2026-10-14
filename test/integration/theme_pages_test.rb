require "test_helper"

# A page under the second theme (theming spec §2 and "Testing"): the theme's
# frame, page template and block template; the default theme's header, image
# block and 404 where the theme holds none; and the CMS's head whatever the
# theme does.
class ThemePagesTest < ActionDispatch::IntegrationTest
  # What the CMS writes into <head> and a theme cannot remove (spec §2), in
  # two groups by where the layout prints them: ahead of the theme's own
  # tags (`layouts/public/_icons`, `_head`) and after them. Each is there
  # EXACTLY ONCE as the CMS's own. The CSP tag is `meta[name=csp-nonce]`,
  # which is what `csp_meta_tag` prints.
  CMS_HEAD_BEFORE_THEME = [
    "title", "meta[name=viewport]", "meta[name=csp-nonce]", "script:not([type])",
    "meta[property='og:title']", "meta[property='og:type']", "meta[property='og:url']", "meta[property='og:locale']",
    "link[rel=canonical]", "link[rel=alternate][hreflang=en]", "link[rel=alternate][hreflang=x-default]"
  ].freeze
  CMS_HEAD_AFTER_THEME = [ "link[rel=stylesheet]", "script[type=importmap]" ].freeze

  # A `_head` that prints tags that are the CMS's to print, behind a marker
  # that says where the theme's part of the head starts.
  GREEDY_HEAD = <<~ERB.freeze
    <meta name="theme-head-starts">
    <link rel="canonical" href="https://elsewhere.example/not-this-page">
    <%= csp_meta_tag %>
    <meta name="csrf-token" content="a-theme-wrote-this">
  ERB

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    SiteSetting.instance.update!(title: "Dana's Notes")
    @home = root_page
    @about = create_page(title: "About")
    result = ContentBlocks::Save.call(ContentBlock.new(owner: @about), attributes: { block_type: "rich_text" },
      translations: { "en" => { body: rich_doc("Words of the about page") } })
    assert result.ok?, result.errors.to_sentence
    publish_changes(@about)
  end

  def head = Nokogiri::HTML5(response.body).at_css("head")

  test "a page under the second theme has the theme's frame, page template and rich-text wrapper, and the default header and footer" do
    with_plain_theme { get "/about" }

    assert_response :success
    assert_select "body > div.plain-frame > main.plain-main > article.plain-page h1", text: "About"
    assert_select "article.plain-page div.plain-text", text: "Words of the about page"
    assert_select ".cs-prose", count: 0
    assert_select "p.plain-crumb a[href='/']", text: "Dana's Notes"
    assert_select "div.plain-frame > header nav[aria-label=Main] a[href='/about']", text: "About"
    assert_select "div.plain-frame > footer [data-controller=theme]"
  end

  test "the default theme draws the same page with its own frame and wrapper" do
    get "/about"

    assert_response :success
    assert_select "body > div > main h1", text: "About"
    assert_select "div.cs-prose", text: "Words of the about page"
    assert_select ".plain-frame, .plain-text, .plain-page", count: 0
  end

  # The elements of <head> in the order they are printed, cut where the
  # theme's part starts: at the first tag `_icons` prints (the default
  # theme's and the second theme's start with a `link[rel=icon]`) or at the
  # greedy theme's marker.
  def head_parts(cut)
    elements = head.element_children.to_a
    at = elements.index { |element| element.matches?(cut) } or flunk "the head has no #{cut}"
    [ fragment(elements[0...at]), fragment(elements[at..]) ]
  end

  def fragment(elements) = Nokogiri::HTML5.fragment(elements.map(&:to_html).join)

  def assert_cms_head(before, whole, theme)
    CMS_HEAD_BEFORE_THEME.each do |selector|
      assert_equal 1, before.css(selector).size, "#{theme}: #{selector} is not there exactly once ahead of the theme's own tags"
    end
    CMS_HEAD_AFTER_THEME.each do |selector|
      assert_equal 1, whole.css(selector).size, "#{theme}: #{selector} is not there exactly once"
    end
    assert_includes before.at_css("script:not([type])").text, 'localStorage.getItem("cs-theme")'
    assert_nil before.at_css("meta[name=csrf-token]"), "#{theme}: the CMS wrote a CSRF token on a public page"
  end

  test "every tag the CMS writes into the head is there exactly once under both themes, ahead of the theme's own" do
    get "/about"
    default_before, default_after = head_parts("link[rel=icon]")
    assert_cms_head default_before, head, "the default theme"

    with_plain_theme { get "/about" }
    themed_before, themed_after = head_parts("link[rel=icon]")
    assert_cms_head themed_before, head, "the second theme"

    described = "meta[property^='og:'], link[rel=canonical], link[rel=alternate]"
    assert_equal default_before.css(described).map(&:to_html), themed_before.css(described).map(&:to_html)
    [ default_after, themed_after ].each do |theme_part|
      assert_empty theme_part.css("title, meta[name=viewport], meta[name=csp-nonce], link[rel=canonical], link[rel=alternate], meta[property^='og:'], meta[name=csrf-token]").map(&:to_html)
    end
  end

  # The rule (spec §2): a theme cannot REMOVE or REPLACE a tag of the CMS's,
  # because each is a line of the layout and none of a replaceable template.
  # Nothing in the rendering stops a theme's `_head` from printing more
  # markup, a tag of the same name included: what holds is that the CMS's
  # own is there once, unchanged, and FIRST, ahead of everything the theme
  # prints. Refusing a `_head` that names such a tag is the contract check's
  # (Task 4), not the renderer's.
  test "a theme whose head prints a canonical link, a CSP tag and a CSRF tag of its own takes none of the CMS's away: each is there once, unchanged and first" do
    get "/about"
    default_before, = head_parts("link[rel=icon]")

    with_theme_copy do |dir|
      dir.join("views/layouts/public/_icons.html.erb").write("")
      dir.join("views/layouts/public/_head.html.erb").write(GREEDY_HEAD)
      Theme.with(Theme.new(path: dir)) { get "/about" }
    end
    before, after = head_parts("meta[name=theme-head-starts]")

    assert_cms_head before, head, "the greedy theme"
    assert_equal "http://www.example.com/about", before.at_css("link[rel=canonical]")["href"]
    assert_equal default_before.css("meta, link").map(&:to_html), before.css("meta, link").map(&:to_html)
    # What the theme printed is on the page, after the CMS's: it is extra
    # markup, which only the contract check can refuse.
    assert_equal [ "https://elsewhere.example/not-this-page" ], after.css("link[rel=canonical]").map { |link| link["href"] }
    assert_equal 1, after.css("meta[name=csp-nonce]").size
    assert_equal 1, after.css("meta[name=csrf-token]").size
    assert_equal 2, head.css("link[rel=canonical]").size
  end

  # `content_for` appends: a second write to the title's slot would be put
  # behind the first, and <title> would read "HijackAbout – Site".
  test "a theme's template that writes to the title's slot changes no title: on a page, on a 404 and with a meta title" do
    with_theme_copy do |dir|
      dir.join("views/pages/show.html.erb").write(%(<% content_for :title, "Hijack" %><article class="plain-page"></article>\n))
      dir.join("views/pages/not_found.html.erb").write(%(<% content_for :title, "Hijack" %><p>Nothing here</p>\n))
      dir.join("views/layouts/public/_frame.html.erb").write(%(<% content_for :title, "Hijack" %><main><%= yield %></main>\n))

      Theme.with(Theme.new(path: dir)) do
        get "/about"
        assert_select "article.plain-page"
        assert_includes response.body, "<title>Dana&#39;s Notes | About</title>"

        get "/no-such-page"
        assert_response :not_found
        assert_select "p", text: "Nothing here"
        assert_includes response.body, "<title>Dana&#39;s Notes</title>"

        assert Pages::Save.call(@about, translations: { "en" => { meta_title: "About us" } }).ok?
        publish_changes(@about)
        get "/about"
        assert_includes response.body, "<title>About us</title>"
      end
    end
  end

  # The head's slot is not a theme's either, for the reason the title's is
  # not: `content_for` appends, so a page or block template that wrote to
  # `:head` would put its tags in the middle of the CMS's part of the head,
  # ahead of the description and the Open Graph tags (and on a 404, alone
  # there). The layout reads no slot: it prints the CMS's tags itself. A
  # theme's own head tags are `layouts/public/_head`, and the folder check
  # refuses a template that writes to the slot
  # (`test/values/theme/check_test.rb`), which is why this folder is handed
  # to `Theme.new`, which checks nothing: what is shown here is that the
  # rendering holds without the check.
  test "a theme's template that writes to the head's slot puts nothing into the head: on a page, in a block and on a 404" do
    with_theme_copy do |dir|
      slot = ->(name) { "<% content_for :head do %><meta name=\"slot-#{name}\" content=\"x\"><link rel=\"canonical\" href=\"https://elsewhere.example/\"><% end %>\n" }
      dir.join("views/pages/show.html.erb").write(slot.("page") + dir.join("views/pages/show.html.erb").read)
      dir.join("views/pages/not_found.html.erb").write(slot.("missing") + "<h1>Nothing here</h1>\n")
      dir.join("views/layouts/public/_frame.html.erb").write(slot.("frame") + "<main><%= yield %></main>\n")
      dir.join("components/blocks/rich_text_component.html.erb").write(slot.("block") + "<div class=\"plain-text\"><%= rich_text(block) %></div>\n")

      Theme.with(Theme.new(path: dir)) do
        get "/about"
        assert_response :success
        assert_select "div.plain-text", minimum: 1
        assert_no_match(/slot-|elsewhere\.example/, response.body)
        assert_select "head meta[property='og:title'][content='About']", count: 1
        assert_select "head meta[property='og:url']", count: 1
        assert_select "head link[rel=canonical]", count: 1

        get "/no-such-page"
        assert_response :not_found
        assert_select "h1", text: "Nothing here"
        assert_no_match(/slot-|elsewhere\.example/, response.body)
      end
    end
  end

  # A PUBLIC PAGE DRAWN UNDER A THEME SETS NO COOKIE, whatever the theme's
  # templates call (theming spec §2: "no CSRF token on a public page, which
  # is the same cookie-less answer for every visitor"). The wall is
  # `PublicController`: it mints no token, commits no session and lets no
  # `Set-Cookie` leave, whether a template wrote to the cookie jar (plain,
  # signed, encrypted, permanent, a delete), to the session, to the flash or
  # to the response's header itself. Forgery protection is off in the test
  # environment, where every token helper prints nothing and no test would
  # notice, so it is switched on here as production has it. The folder is
  # handed to `Theme.new`, which checks nothing: `Theme::Check` refuses
  # these words with a clear message, and this is what holds for the
  # spelling it does not see.
  GRASPING = <<~ERB.freeze
    <%= csrf_meta_tags %>
    <meta name="minted" content="<%= form_authenticity_token %>">
    <% session[:visitor] = "seen" %>
    <% flash[:notice] = "hello" %>
    <% cookies[:seen] = "1" %>
    <% cookies.signed[:who] = "someone" %>
    <% cookies.encrypted[:what] = "something" %>
    <% cookies.permanent[:forever] = "1" %>
    <% cookies.delete(:session_id) %>
    <% response.set_cookie(:by_hand, "1") %>
    <% response.headers["Set-Cookie"] = [ response.headers["Set-Cookie"], "raw=1; path=/" ].flatten.compact %>
  ERB

  def with_forgery_protection
    before = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = before
  end

  test "a public page drawn under a theme sets no cookie and carries no token: a form, the CSRF tags, a token asked for, and a write to the session, the flash, the cookie jar and the header" do
    with_theme_copy do |dir|
      dir.join("views/layouts/public/_head.html.erb").write(GRASPING)
      dir.join("views/pages/not_found.html.erb").write("<h1>Nothing here</h1>\n")
      dir.join("views/layouts/public/_frame.html.erb").write(<<~ERB)
        <main><%= yield %></main>
        <%= form_with url: "/newsletter", method: :post do |form| %><%= form.submit "Join" %><% end %>
        <%= button_to "Vote", "/vote" %>
        <%= form_with url: "/search", method: :get do |form| %><%= form.search_field :q %><% end %>
      ERB

      with_forgery_protection do
        Theme.with(Theme.new(path: dir)) do
          [ "/about", "/no-such-page" ].each do |address|
            get address

            assert_select "form[action='/newsletter']", count: 1
            assert_select "form[action='/search'][method=get] input[name=q]", count: 1
            assert_nil response.headers["Set-Cookie"], "#{address} set a cookie"
            assert_empty cookies.to_hash, "#{address} left a cookie"
            assert_select "input[name=authenticity_token]", count: 0
            assert_select "meta[name=csrf-token], meta[name=csrf-param]", count: 0
            assert_select "meta[name=minted]" do |tags|
              assert_empty tags.first["content"].to_s, "a token was minted for a public page"
            end
          end
        end
      end
    end
  end

  # The same wall, followed by someone who is signed in: an editor reads the
  # public site in the browser they work in. The public page must neither
  # set a cookie nor take one away (a session that is not committed is not
  # dropped either), and CS Studio must still know them afterwards.
  test "a signed-in editor reads a public page under a grasping theme and is still signed in: no cookie set, none changed, none taken away" do
    with_theme_copy do |dir|
      dir.join("views/layouts/public/_head.html.erb").write(GRASPING)

      with_forgery_protection do
        get admin_sign_in_path
        token = css_select("input[name=authenticity_token]").first["value"]
        post admin_sign_in_path, params: { email_address: users(:one).email_address, password: "password", authenticity_token: token }
        assert cookies[:session_id].present?, "signed in"
        get "/cs-studio"
        assert_response :success
        before = cookies.to_hash

        Theme.with(Theme.new(path: dir)) do
          [ "/about", "/no-such-page" ].each do |address|
            get address

            assert_nil response.headers["Set-Cookie"], "#{address} set or cleared a cookie"
            assert_equal before, cookies.to_hash, "#{address} changed the browser's cookies"
          end
        end

        get "/cs-studio"
        assert_response :success
        assert_select "nav[aria-label='Modules']"
      end
    end
  end

  # The preview is the other controller that draws a theme, and it is none
  # of the above: signed in, private, never cached. A form there carries its
  # token, as any form of CS Studio does.
  test "the preview, which is private and signed in, keeps its token and its cookies: the wall is the public controller's alone" do
    with_theme_copy do |dir|
      dir.join("views/layouts/public/_frame.html.erb").write(
        "<main><%= yield %></main>\n<%= form_with url: \"/newsletter\", method: :post do |form| %><%= form.submit \"Join\" %><% end %>\n" \
        "<% cookies[:seen] = \"1\" %>\n")
      sign_in_as users(:one)

      with_forgery_protection do
        Theme.with(Theme.new(path: dir)) { get "/preview/about" }
      end

      assert_response :success
      assert_select "form[action='/newsletter'] input[name=authenticity_token]", count: 1
      assert_equal "1", cookies[:seen], "a cookie a template sets in the preview is the preview's to set"
    end
  end

  # A RELOAD THAT REFUSES THE THEME LEAVES THE APPLICATION WHOLE. In
  # development a changed file of the theme reloads the application, and
  # the check runs again in `to_prepare`. Raising there (as the boot does,
  # and should) would stop the chain of prepare blocks where it is raised,
  # and the reloader would count the reload as done. The theme is prepared
  # last in the types' block (config/initializers/types.rb), after the types
  # it is checked against; when it had a block of its own before the
  # types', a raise left the registries empty and the next request was
  # drawn with no block types, right after the mistake the check is there
  # to explain. So on a reload the refusal is kept on the Theme and every
  # public page raises it, and the registries are still asserted here.
  test "a theme refused on a reload leaves the registries prepared and CS Studio working, and every public page says why until it is corrected" do
    with_theme_copy do |dir|
      dir.join("views/pages/shwo.html.erb").write("x")
      bad = ThemeFolder.new(dir)

      with_singleton_override(ThemeFolder, :current, -> { bad }) do
        # The registries are emptied first, as a code reload leaves them
        # (their classes are loaded anew): `prepare!` alone clears nothing,
        # so without this the three assertions below would hold whether or
        # not the prepare ran. The theme is prepared last in the types'
        # block (config/initializers/types.rb), after the registries it is
        # checked against.
        names = BlockTypes.names
        [ BlockTypes, ContentTypes ].each(&:reset!)
        AccessControl::Permissions.reset!
        assert_empty BlockTypes.all

        Rails.application.reloader.prepare!

        assert_includes Theme.current.refusal.message, "views/pages/shwo.html.erb is not part of the theme contract"
        assert_equal names, BlockTypes.names
        assert_not_empty ContentTypes.all
        assert AccessControl::Permissions.all.any?

        [ "/about", "/", "/no-such-page" ].each do |address|
          error = assert_raises(ThemeFolder::Invalid) { get address }
          assert_includes error.message, "views/pages/shwo.html.erb is not part of the theme contract"
        end
        sign_in_as users(:one)
        assert_includes assert_raises(ThemeFolder::Invalid) { get "/preview/about" }.message, "shwo"
        get "/cs-studio"
        assert_response :success

        dir.join("views/pages/shwo.html.erb").delete
        Rails.application.reloader.prepare!
        assert_nil Theme.current.refusal
        get "/about"
        assert_response :success
        assert_select "article.plain-page"
      end
    end
  ensure
    Rails.application.reloader.prepare!
  end

  # The same, for what the check did not expect: a note saved at the theme's
  # top while a development server runs. It was a `KeyError` out of the
  # reloader's prepare, which left the registries empty: the failure the
  # test above is about, reached by another way.
  test "a file that appears at a theme folder's top is a refusal on the next reload, not an exception: the registries are prepared and the public page names the file" do
    with_theme_copy do |dir|
      folder = ThemeFolder.new(dir)
      dir.join("notes.txt").write("to do")
      FileUtils.rm_r(dir.join("javascript"))
      dir.join("javascript").write("not a folder")

      with_singleton_override(ThemeFolder, :current, -> { folder }) do
        names = BlockTypes.names
        [ BlockTypes, ContentTypes ].each(&:reset!)
        AccessControl::Permissions.reset!

        Rails.application.reloader.prepare!

        assert_includes Theme.current.refusal.message, "  - notes.txt is not part of a theme."
        assert_includes Theme.current.refusal.message, "  - javascript is not part of a theme."
        assert_equal names, BlockTypes.names
        assert_not_empty ContentTypes.all
        assert_includes assert_raises(ThemeFolder::Invalid) { get "/about" }.message, "notes.txt is not part of a theme"
        sign_in_as users(:one)
        get "/cs-studio"
        assert_response :success
      end
    end
  ensure
    Rails.application.reloader.prepare!
  end

  test "an empty theme draws the homepage as the default theme does" do
    get "/"
    default = response.body

    Dir.mktmpdir("theme") do |dir|
      Theme.with(Theme.load(ThemeFolder.new(dir))) { get "/" }
    end

    assert_response :success
    assert_equal default, response.body
  end

  test "the title is the theme's pattern on one line, escaped once" do
    with_plain_theme do
      get "/about"
      assert_includes response.body, "<title>Dana&#39;s Notes | About</title>"

      get "/"
      assert_includes response.body, "<title>Dana&#39;s Notes</title>"

      get "/no-such-page"
      assert_response :not_found
      assert_includes response.body, "<title>Dana&#39;s Notes</title>"
    end

    get "/about"
    assert_includes response.body, "<title>About – Dana&#39;s Notes</title>"
    get "/no-such-page"
    assert_includes response.body, "<title>Dana&#39;s Notes</title>"
  end

  test "a meta title an editor typed is taken as written, whatever the theme's pattern" do
    assert Pages::Save.call(@about, translations: { "en" => { meta_title: "About us & them" } }).ok?
    publish_changes(@about)

    with_plain_theme { get "/about" }

    assert_includes response.body, "<title>About us &amp; them</title>"
  end

  test "the icons and the theme's own head tags are the theme's, and the default theme keeps its own" do
    with_plain_theme { get "/about" }

    assert_select "head link[rel=icon][href*='plain-mark']", count: 1
    assert_select "head link[rel=icon][href='/icon.png']", count: 0
    assert_select "head link[rel='apple-touch-icon']", count: 0
    assert_select "head meta[name='theme-color'][content='#123456']"
    assert_select "head meta[name='application-name']", count: 0

    get "/about"

    assert_select "head link[rel=icon][href='/icon.png']"
    assert_select "head link[rel='apple-touch-icon'][href='/icon.png']"
    assert_select "head meta[name='application-name'][content='ContentSpiel']"
    assert_select "head meta[name='theme-color']", count: 0
  end

  test "a template the theme does not hold is the default theme's: the 404 inside the theme's frame" do
    with_plain_theme { get "/no-such-page" }

    assert_response :not_found
    assert_select "div.plain-frame > main.plain-main h1", text: "Page not found"
  end

  test "a post list the theme replaced is drawn by it, and the post's page by the default" do
    blog = create_page(title: "Blog")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).ok?
    publish_changes(blog)
    create_post(title: "First post")

    with_plain_theme { get "/blog" }

    assert_select "ol.plain-posts li a[href='/blog/first-post']", text: "First post"

    with_plain_theme { get "/blog/first-post" }

    assert_select "div.plain-frame article.content-block--post-list-detail h1", text: "First post"
  end

  # The Code block's template is a theme's to replace (code block spec §5):
  # the third theme's is written from the nine names the contract gives it,
  # each of which is drawn here, and the markup the copy script asks for.
  # The second theme holds no Code template, so under it the block is the
  # default's.
  test "a theme replaces the Code block's template from the contract's names alone, and a theme that does not is drawn the default one" do
    docs = create_page(title: "Docs")
    result = ContentBlocks::Save.call(ContentBlock.new(owner: docs), attributes: { block_type: "code", settings: { "language" => "ruby", "filename" => "<a>.rb", "code" => "a = 1\n  b = \"<b>\"" } },
      translations: { "en" => { caption: "Two lines" } })
    assert result.ok?, result.errors.to_sentence
    publish_changes(docs)

    with_code_theme { get "/docs" }

    assert_response :success
    assert_select "div.plain-code[data-language='ruby'][data-characters='17'][data-block='#{result.record.id}'][data-page='#{docs.id}']", count: 1
    assert_select "div.plain-code[data-controller='code-copy'][data-code-copy-label-value='Copy'][data-code-copy-copied-value='Copied'][data-code-copy-failed-value='Not copied']" do
      assert_select "div.plain-code__bar:not([hidden]):not([data-code-copy-target]) p.plain-code__file#code-#{result.record.id}-file", text: "<a>.rb"
      assert_select "button[aria-describedby='code-#{result.record.id}-file']", count: 1
      assert_select "p.plain-code__language", text: "Ruby"
      assert_select "button[type=button][hidden][aria-label='Copy code'][data-code-copy-target='button'][data-action='code-copy#copy']", text: "Copy"
      assert_select "[role=status][data-code-copy-target='status']", count: 1
      assert_select "pre[data-code-copy-target='source'] b.syn-constant[data-role='constant']", text: "1"
      assert_select "pre[data-code-copy-target='source'] b[data-role='string']", text: "\"<b>\""
      assert_select "p.plain-code__caption", text: "Two lines"
    end
    assert_equal "a = 1\n  b = \"<b>\"", Nokogiri::HTML5(response.body).at_css("div.plain-code pre").text, "what the script copies is the stored code, to the character"
    assert_select "figure.content-block--code", count: 0
    assert_select "div.plain-code b b, div.plain-code pre a", count: 0

    with_plain_theme { get "/docs" }

    assert_response :success
    assert_select "div.plain-frame figure.content-block--code pre span.syn-constant", text: "1"
    assert_select "div.plain-code", count: 0
  end

  test "the third theme is sound, checked deeply too: a Code template of the contract's names and a stylesheet of the seven tokens for both schemes" do
    folder = ThemeFolder.new(ThemeTestHelper::CODE)

    assert_empty Theme::Check.problems(folder, deep: true)
    assert_equal %w[assets/stylesheets/theme.css components/blocks/code_component.html.erb], folder.files
    template = folder.read("components/blocks/code_component.html.erb")
    Theme::Contract.components.fetch("blocks/code_component").each { |name| assert_match(/\b#{name}\b/, template, "the template calls #{name}") }
    assert_no_match(/head_attributes|bare\?|settings|html_safe|raw\b|safe_join|<%==/, template, "nothing the contract does not name, and no string marked safe")
    css = folder.read("assets/stylesheets/theme.css")
    [ /:root, \[data-theme="light"\]\s*\{(.*?)\}/m, /^\[data-theme="dark"\]\s*\{(.*?)\}/m ].each do |block|
      assert_equal CodeHighlight::ROLES.map { |role| "--th-syn-#{role}" }, css[block, 1].to_s.scan(/(--th-[\w-]+):/).flatten
    end
  end

  test "the preview is drawn by the theme too, with the CMS's preview bar" do
    sign_in_as users(:one)

    with_plain_theme { get "/preview/about" }

    assert_response :success
    assert_equal "noindex", response.headers["X-Robots-Tag"]
    assert_select "body > [role=region][aria-label=Preview]"
    assert_select "body > div.plain-frame article.plain-page h1", text: "About"
    assert_select "head link[rel=canonical]", count: 0
  end

  # The dispatch's ruling: the head tags and the bar moved from pages/show
  # into the layout so that a theme which replaces pages/show keeps them.
  # The second theme's pages/show renders neither (it is five lines).
  test "a theme that replaces the page template still gets the description, the Open Graph tags and the preview bar" do
    assert Pages::Save.call(@about, translations: { "en" => { meta_description: "Who writes here" } }).ok?
    publish_changes(@about)
    assert_no_match(/seo_meta|preview_banner/, ThemeTestHelper::PLAIN.join("views/pages/show.html.erb").read)

    with_plain_theme { get "/about" }

    assert_select "article.plain-page"
    assert_select "head meta[name=description][content='Who writes here']", count: 1
    assert_select "head meta[property='og:title'][content='About']", count: 1
    assert_select "head meta[property='og:description'][content='Who writes here']", count: 1
    assert_select "head meta[property='og:url'][content='http://www.example.com/about']", count: 1
    assert_select "[role=region][aria-label=Preview]", count: 0

    sign_in_as users(:one)
    with_plain_theme { get "/preview/about" }

    assert_select "article.plain-page"
    assert_select "head meta[property='og:title'][content='About']", count: 1
    assert_select "html.scroll-pt-9 > body.pt-9 > [role=region][aria-label=Preview]:first-child", count: 1
  end

  # `assign_record` can leave @page and @post set and still answer false (a
  # post no block of its page lists any more), and the preview answers 404
  # for a post whose listing page the editor may not read. The layout
  # collects the head tags itself now, so it must not describe a record on a
  # response that says there is none.
  test "a 404 that had a record in hand describes none: the site's title and no description or Open Graph tag" do
    blog = create_page(title: "Blog", translations: { "en" => { title: "Blog", meta_description: "The blog of secrets" } })
    assert ContentBlocks::Save.call(ContentBlock.new(owner: blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).ok?
    publish_changes(blog)
    create_post(title: "Hello")
    # The address is the copy's, the preview draws the rows: the rows list
    # the post no longer, so the page and the post are both in hand when the
    # preview answers that there is nothing to draw the post on.
    assert ContentBlocks::Destroy.call(blog.content_blocks.sole).ok?

    sign_in_as users(:one)
    get "/preview/blog/hello"

    assert_response :not_found
    assert_includes response.body, "<title>Dana&#39;s Notes</title>"
    assert_select "head meta[property^='og:'], head meta[name=description]", count: 0
    assert_no_match(/The blog of secrets/, response.body)
  end

  # The same 404s name no address either: a canonical link or an hreflang
  # alternate on a response that says "not found" tells a search engine that
  # the missing page is the record's own address in every language. The
  # preview never prints a canonical, so the public site's 404 is made here
  # the one way it comes about: the post's stored address outlives the list
  # that gave it one (`PublicPageRendering#assign_record`), which no write
  # path leaves behind and a test can only say by answering for the list.
  test "a 404 that had a record in hand names no canonical address and no other language's, in the preview and in public" do
    blog = create_page(title: "Blog")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).ok?
    publish_changes(blog)
    create_post(title: "Hello")

    get "/blog/hello"
    assert_response :success
    assert_select "head link[rel=canonical]", count: 1
    assert_select "head link[rel=alternate][hreflang]", minimum: 2

    # The address is answered as it is (`PublicSite::Paths.canonical_page`
    # asks with `tags:`), and the controller's own question, the one that
    # finds the page and the post in hand with no list between them, "no".
    listing = Publishing::Listing.method(:lists?)
    asked = 0
    Publishing::Listing.define_singleton_method(:lists?) do |block, post, tags: nil|
      next listing.call(block, post, tags: tags) if tags

      asked += 1
      false
    end
    begin
      get "/blog/hello"
    ensure
      Publishing::Listing.define_singleton_method(:lists?, listing)
    end
    assert_equal 1, asked, "the 404 is the controller's, after it assigned the page and the post"
    assert_response :not_found
    assert_select "head link[rel=canonical], head link[rel=alternate]", count: 0

    assert ContentBlocks::Destroy.call(blog.content_blocks.sole).ok?
    sign_in_as users(:one)
    get "/preview/blog/hello"

    assert_response :not_found
    assert_select "head link[rel=canonical], head link[rel=alternate]", count: 0
  end

  # NOTHING OF A THEME REACHES CS STUDIO, SIGN-IN OR SETUP. A theme's views
  # are on the view path of the two public controllers only
  # (`PublicPageRendering#look_in_the_theme_first`). These tests can fail:
  # the theme they use holds a file at the very name of each private layout
  # and of one view of each private screen, every one of them the marker and
  # nothing else, so a controller that gained the theme's path would draw
  # the marker in place of its own page. (Seen failing, all three, with the
  # `before_action` moved to `ApplicationController`.) The files are written
  # into a copy and not kept in `test/fixtures/themes/plain`: a folder that
  # holds `views/layouts/admin.html.erb` is not a theme, and the folder
  # check refuses it (`lib/theme_folder.rb`); the copy is handed to
  # `Theme.new`, which checks nothing, because what is tested here is the
  # second fence, behind the check.
  LEAK = "THEME-LEAK".freeze
  PRIVATE_VIEWS = %w[
    layouts/admin layouts/product layouts/setup layouts/mailer
    admin/dashboard/show admin/sessions/new admin/passwords/new admin/passwords/edit setup/token setup/system_check
    passwords_mailer/reset
  ].freeze
  # A mail has a text part with a template and a layout of its own.
  PRIVATE_TEXT_VIEWS = %w[layouts/mailer passwords_mailer/reset].freeze

  def with_leaking_theme
    with_theme_copy do |dir|
      PRIVATE_VIEWS.each do |name|
        assert Rails.root.join("app/views/#{name}.html.erb").file?, "#{name} is no view of the CMS any more: name one that is"
        file = dir.join("views/#{name}.html.erb")
        file.dirname.mkpath
        file.write("#{LEAK}\n")
      end
      PRIVATE_TEXT_VIEWS.each do |name|
        assert Rails.root.join("app/views/#{name}.text.erb").file?, "#{name}.text.erb is no view of the CMS any more: name one that is"
        dir.join("views/#{name}.text.erb").write("#{LEAK}\n")
      end
      # The control: the same folder IS where a public page's template comes from.
      dir.join("views/pages/not_found.html.erb").write("<p>THEME-FOUND</p>\n")
      @leaking_views = dir.join("views").to_s
      Theme.with(Theme.new(path: dir)) { yield }
    end
  end

  def assert_theme_reached_the_public_page
    get "/no-such-page"
    assert_includes response.body, "THEME-FOUND", "the control failed: the theme's folder is on no path at all"
    assert_equal @leaking_views, controller.lookup_context.view_paths.first.to_s
  end

  def assert_no_theme_here
    assert_response :success
    assert_no_match(/#{LEAK}|plain-frame|plain-mark|plain-page/, response.body)
    assert_not_includes controller.lookup_context.view_paths.map(&:to_s), @leaking_views
  end

  test "nothing of a theme reaches sign-in: a theme's file named as the product layout or the sign-in view is never drawn" do
    with_leaking_theme do
      assert_theme_reached_the_public_page

      get admin_sign_in_path
      assert_no_theme_here
      assert_select "form input[type=password]"
    end
  end

  test "nothing of a theme reaches CS Studio: a theme's file named as the admin layout or the dashboard is never drawn" do
    with_leaking_theme do
      assert_theme_reached_the_public_page

      sign_in_as users(:one)
      get "/cs-studio"
      assert_no_theme_here
      assert_select "head meta[name='theme-color'][content='#123456']", count: 0
    end
  end

  # The two the three tests above never asked: the password pages are a
  # second controller under the product layout (a path given to that
  # controller alone would be seen by no other test), and a mail is drawn
  # outside any request, by a class that is no controller at all.
  test "nothing of a theme reaches the password pages or a mail: a theme's file named as either's view or layout is never drawn" do
    with_leaking_theme do
      assert_theme_reached_the_public_page

      get new_admin_password_path
      assert_no_theme_here
      assert_equal "Admin::PasswordsController", controller.class.name
      assert_select "form input[type=email]"

      get admin_edit_password_path
      assert_no_theme_here

      mail = PasswordsMailer.reset(users(:one), origin: "http://www.example.com").deliver_now
      assert_equal [ users(:one).email_address ], mail.to
      [ mail.html_part, mail.text_part ].each do |part|
        assert_no_match(/#{LEAK}|plain-frame|plain-mark|plain-page/, part.body.to_s)
        assert_includes part.body.to_s, "/password/edit#"
      end
      assert_not_includes PasswordsMailer.view_paths.map(&:to_s), @leaking_views
    end
  end

  test "nothing of a theme reaches setup: a theme's file named as the setup layout or a step is never drawn" do
    start_fresh_install

    with_leaking_theme do
      get setup_path
      follow_redirect! while response.redirect?
      assert_no_theme_here
      assert_equal "SetupController", controller.class.name

      verify_setup_token
      get setup_step_path("system_check")
      assert_no_theme_here
      assert_includes response.body, "File storage"
    end
  end

  test "a theme's page template that raises is an error that names the theme's file, not a fallback" do
    with_theme_copy do |dir|
      dir.join("views/pages/show.html.erb").write("<p><%= no_such_helper_anywhere %></p>\n")

      error = assert_raises(ActionView::Template::Error) do
        Theme.with(Theme.new(path: dir)) { get "/about" }
      end

      assert_includes error.message, "no_such_helper_anywhere"
      assert_includes error.backtrace.join("\n"), dir.join("views/pages/show.html.erb").to_s
    end
  end

  test "the second theme draws the section's tree, the crumbs, the contents and previous and next" do
    guide = create_page(title: "Guide")
    start = create_page(title: "Start", parent: guide)
    create_page(title: "Write", parent: guide)
    result = ContentBlocks::Save.call(ContentBlock.new(owner: start), attributes: { block_type: "rich_text" },
      translations: { "en" => { body: rich_doc("## Setup\n\nFirst.\n\n## Setup\n\nAgain.") } })
    assert result.ok?, result.errors.to_sentence
    publish_changes(start)

    with_plain_theme { get "/guide/start" }

    assert_response :success
    assert_select "nav.plain-tree > ul > li.is-open > a[href='/guide']", text: "Guide"
    assert_select "nav.plain-tree a[href='/guide/start'][aria-current=page]", text: "Start"
    assert_select "nav.plain-tree a[href='/guide/write']", text: "Write"
    assert_select "nav.plain-tree a[aria-current=page]", count: 1
    assert_select "p.plain-crumb a[href='/guide']", text: "Guide"
    assert_select "ol.plain-contents a[href='#setup']", text: "Setup"
    assert_select "ol.plain-contents a[href='#setup-2']", text: "Setup"
    assert_select "article.plain-page div.plain-text h2#setup"
    assert_select "article.plain-page div.plain-text h2#setup-2"
    assert_select "nav.plain-neighbours a[rel=prev][href='/guide']", text: "Guide"
    assert_select "nav.plain-neighbours a[rel=next][href='/guide/write']", text: "Write"
  end

  test "the homepage has no section, and a 404 no tree" do
    with_plain_theme do
      get "/"
      assert_select "nav.plain-tree", count: 0

      get "/no-such-page"
      assert_response :not_found
      assert_select "nav.plain-tree", count: 0
    end
  end

  test "the tree in another language links that language's addresses" do
    guide = create_page(title: "Guide")
    create_page(title: "Start", parent: guide)

    with_plain_theme { get "/de/guide/start" }

    assert_response :success
    assert_select "nav.plain-tree a[href='/de/guide']"
    assert_select "nav.plain-tree a[href='/de/guide/start'][aria-current=page]"
  end

  # A 404 can have a page in hand (`PublicPageRendering#assign_record`: a
  # post whose list is gone), and a 404 says nothing of a record. The second
  # theme's frame asks for the section on every page with no condition of
  # its own: the helpers answer nothing on a 404, and `page_found?` is what
  # the frame asks before it prints the page's title.
  test "a 404 that had a page in hand draws no tree and nothing of the page; the same page found draws both" do
    blog = create_page(title: "Blog")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).ok?
    publish_changes(blog)
    create_post(title: "Hello")

    with_plain_theme { get "/blog/hello" }
    assert_response :success
    assert_select "nav.plain-tree a[href='/blog']"
    assert_select "p.plain-here", text: "Blog"

    assert ContentBlocks::Destroy.call(blog.content_blocks.sole).ok?
    sign_in_as users(:one)
    with_plain_theme { get "/preview/blog/hello" }

    assert_response :not_found
    assert_select "div.plain-frame"
    assert_select "nav.plain-tree", count: 0
    assert_select "p.plain-here", count: 0
  end

  # The fixture's post list draws each title as a heading in a list item:
  # a list of OTHER texts, not a heading of this page's.
  test "a post list's titles are not in the page's contents, and get no id" do
    blog = create_page(title: "Blog")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: blog), attributes: { block_type: "rich_text" }, translations: { "en" => { body: rich_doc("## About this blog") } }).ok?
    assert ContentBlocks::Save.call(ContentBlock.new(owner: blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).ok?
    publish_changes(blog)
    create_post(title: "First post")

    with_plain_theme { get "/blog" }

    assert_select "ol.plain-contents a", count: 1
    assert_select "ol.plain-contents a[href='#about-this-blog']"
    assert_select "ol.plain-posts li h3", text: "First post"
    assert_select "ol.plain-posts li h3[id]", count: 0
  end

  # The same, the other way round: a heading an AUTHOR wrote inside a list
  # item of the text is the text's, and is in the contents with its id.
  test "a heading inside a list item of a page's text is in the contents and has its id, under a theme whose wrapper is its own" do
    document = { "type" => "doc", "content" => [
      { "type" => "heading", "attrs" => { "level" => 2 }, "content" => [ { "type" => "text", "text" => "Steps" } ] },
      { "type" => "orderedList", "content" => [
        { "type" => "listItem", "content" => [
          { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "First" } ] },
          { "type" => "heading", "attrs" => { "level" => 3 }, "content" => [ { "type" => "text", "text" => "Inside an item" } ] }
        ] }
      ] }
    ] }
    page = create_page(title: "How to")
    result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }, translations: { "en" => { body: document } })
    assert result.ok?, result.errors.to_sentence
    publish_changes(page)

    with_plain_theme { get "/how-to" }

    assert_response :success
    assert_select "div.plain-text li h3#inside-an-item", text: "Inside an item"
    assert_select "ol.plain-contents a[href='#inside-an-item']", count: 1
    assert_select "ol.plain-contents a", count: 2
  end

  test "the preview's tree links the preview's addresses and shows the rows' titles; the public one shows the published" do
    guide = create_page(title: "Guide")
    start = create_page(title: "Start", parent: guide)
    assert Pages::Save.call(start, translations: { "en" => { title: "Start UNPUBLISHED" } }).ok?

    with_plain_theme { get "/guide/start" }
    assert_select "nav.plain-tree a[href='/guide/start'][aria-current=page]", text: "Start"
    assert_not_includes response.body, "UNPUBLISHED"

    sign_in_as users(:one)
    with_plain_theme { get "/preview/guide/start" }
    assert_select "nav.plain-tree a[href='/preview/guide/start'][aria-current=page]", text: "Start UNPUBLISHED"
    assert_select "p.plain-crumb a[href='/preview/guide']", text: "Guide"
  end

  # WHY `Theme::Check` REFUSES `cache` IN A THEME'S TEMPLATE. The public page
  # and the preview draw the SAME template of the theme, and Rails keys a
  # fragment by the template's path and digest and the name it was given:
  # nothing in the key says which of the two is drawing. Whichever comes
  # first fills the entry. Here an editor's preview fills it with a title
  # that is not published, and the next visitor of the public page is
  # served it. Caching is off in the test environment, so it is switched on
  # here with a store of this test's own, as production has it (Solid
  # Cache); the folder goes through `Theme.new`, which checks nothing.
  #
  # This test shows the leak ON PURPOSE and passes while it is there. Should
  # it fail one day (Rails keying a fragment by the controller, say), the
  # refusal can be thought about again; until then it is the reason.
  test "a fragment a theme's template caches is shared by the preview and the public page: an unpublished title reaches a visitor, which is why the check refuses it" do
    assert Pages::Save.call(@about, translations: { "en" => { title: "About UNPUBLISHED" } }).ok?

    with_theme_copy do |dir|
      dir.join("views/layouts/public/_frame.html.erb").write(<<~ERB)
        <main><%= yield %></main>
        <% cache "footer" do %><p class="cached"><%= translated(@page, :title) if @page %></p><% end %>
      ERB

      with_caching do
        Theme.with(Theme.new(path: dir)) do
          get "/about"
          assert_select "p.cached", text: "About"
        end
      end

      with_caching do
        Theme.with(Theme.new(path: dir)) do
          sign_in_as users(:one)
          get "/preview/about"
          assert_select "p.cached", text: "About UNPUBLISHED"

          delete admin_sign_out_path
          get "/about"
          assert_response :success
          assert_equal "max-age=0, public, must-revalidate", response.headers["Cache-Control"]
          assert_select "p.cached", { text: "About UNPUBLISHED" }, "the leak is gone: read the comment above this test"
        end
      end
    end
  end

  def with_caching
    before = [ ActionController::Base.perform_caching, ActionController::Base.cache_store ]
    ActionController::Base.perform_caching = true
    ActionController::Base.cache_store = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    ActionController::Base.perform_caching, ActionController::Base.cache_store = before
  end

  # The tree on a page is other pages' titles: the page's ETag must move when
  # one of them is published, or a visitor's cached page keeps the old tree.
  test "a page a visitor has is asked for again when another page of its tree is published under a new title" do
    guide = create_page(title: "Guide")
    create_page(title: "Start", parent: guide)
    write = create_page(title: "Write", parent: guide)

    with_plain_theme do
      get "/guide/start"
      etag = response.headers["ETag"]
      get "/guide/start", headers: { "If-None-Match" => etag }
      assert_response :not_modified

      assert Pages::Save.call(write, translations: { "en" => { title: "Write well" } }).ok?
      publish_changes(write)
      get "/guide/start", headers: { "If-None-Match" => etag }

      assert_response :success
      assert_select "nav.plain-tree a[href='/guide/write']", text: "Write well"
    end
  end

  # Spec §5 and §7: a body is rendered once, cached by its document's digest,
  # and is the same HTML in CS Studio, for the MCP server and on the site.
  # `with_heading_ids` works on what the page's template captured, after
  # that cache. With a real store: the suite's null store would never hand a
  # cached render back.
  test "heading ids are on the page a theme draws and not in the cached render of the text" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    result = ContentBlocks::Save.call(ContentBlock.new(owner: @about), attributes: { block_type: "rich_text" },
      translations: { "en" => { body: rich_doc("## Setup\n\nFirst.") } })
    assert result.ok?, result.errors.to_sentence
    publish_changes(@about)
    document = Locales.read(result.record, :body, locale: "en")
    plain = %(<h2>Setup</h2>)

    assert_includes document.to_html(locale: :en, urls: PublicSite::Urls.new), plain
    with_plain_theme { get "/about" }
    assert_select "article.plain-page h2#setup", text: "Setup"

    hits = []
    ActiveSupport::Notifications.subscribed(->(*, payload) { hits << payload[:hit] }, "cache_read.active_support") do
      @cached = document.to_html(locale: :en, urls: PublicSite::Urls.new)
    end
    assert_equal [ true ], hits, "the render was not served from the cache: this test shows nothing"
    assert_includes @cached, plain, "an id reached the cached render"
    assert_not_includes @cached, "id="

    get "/about"
    assert_select "div.cs-prose h2", text: "Setup"
    assert_select "div.cs-prose h2[id]", count: 0
    with_plain_theme { get "/about" }
    assert_select "article.plain-page h2#setup", text: "Setup"
  ensure
    Rails.cache = original_cache
  end
end
