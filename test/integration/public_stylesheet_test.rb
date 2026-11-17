require "test_helper"

# The public stylesheet drawn into the page or linked (`Theme::Stylesheet`,
# `ThemeCss::INLINE_LIMIT`; `docs/reference/theming.md`, "Drawn into the
# page, or linked"). The suite's built stylesheet is the default theme's,
# which is under the limit; the linked way is shown by a lower limit, or by
# the site's mode (Settings → Page speed, `SiteSetting#stylesheet_mode`).
class PublicStylesheetTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @about = create_page(title: "About")
  end

  def built = Rails.application.assets.load_path.find("theme.css")

  def drawn_style = css_select("head style[data-turbo-track=reload]")

  def link_header = response.headers["Link"].to_s

  # A stand-in for the built file, for a stylesheet the suite does not build.
  FakeAsset = Data.define(:digest, :content, :compiled_content)

  def stylesheet_of(css, digest:) = Theme::Stylesheet.new(FakeAsset.new(digest: digest, content: css, compiled_content: css), limit: ThemeCss::INLINE_LIMIT)

  test "a small stylesheet is drawn into the head as the CSS Propshaft serves, with no link and no preload header, on every kind of public page" do
    assert ThemeCss.inline_for?(:automatic, ThemeCss.compressed_size(built.content)), "the default theme's built stylesheet is under the limit"
    assert_equal ThemeCss.compressed_size(built.content), Theme::Stylesheet.current.compressed_size

    [ "/", "/about", "/no-such-page" ].each do |path|
      get path
      assert_includes [ 200, 404 ], response.status

      assert_empty css_select("link[rel=stylesheet]"), "#{path}: a stylesheet drawn in is linked as well"
      assert_not_includes link_header, "theme", "#{path}: a stylesheet drawn in is preloaded"
      assert_equal 1, drawn_style.size, "#{path}: one theme stylesheet in the head"
      assert_equal built.compiled_content.force_encoding(Encoding::UTF_8), drawn_style.first.text, "#{path}: the CSS is the served file's, byte for byte"
    end
  end

  test "a drawn-in stylesheet names its fonts by their absolute digested address, which is served" do
    get "/about"
    fonts = drawn_style.first.text.scan(/url\("([^"]+\.woff2)"\)/).flatten
    assert_not_empty fonts, "the default theme's stylesheet names its fonts"
    assert fonts.all? { |url| url.match?(%r{\A/assets/[\w-]+-\h{8}\.woff2\z}) }, "a font is named relative to the stylesheet: #{fonts.first(3)}"

    get fonts.first
    assert_response :success
  end

  test "a stylesheet over the limit is linked, tracked by Turbo, and preloaded by its header, as before" do
    Theme::Stylesheet.with_limit(1) do
      get "/about"
    end

    assert_response :success
    assert_empty drawn_style
    links = css_select("link[rel=stylesheet]")
    assert_equal 1, links.size
    assert_match %r{\A/assets/theme-\h+\.css\z}, links.first["href"]
    assert_equal "reload", links.first["data-turbo-track"]
    assert_includes link_header, "<#{links.first["href"]}>; rel=preload; as=style"
  end

  # Settings → Page speed: "inline" draws in a stylesheet over the limit,
  # "file" links one under it, each with what goes with that way (the
  # preload header for a link and nothing for a `<style>`), and Automatic is
  # what a site does by default.
  test "the site's mode decides: Automatic by the size, Always in the page whatever the size, Always a separate file whatever the size" do
    site = site_settings(:default)
    assert_equal "automatic", site.stylesheet_mode, "a site starts on Automatic"

    site.update!(stylesheet_mode: "file")
    get "/about"
    assert_response :success
    assert_empty drawn_style, "a small stylesheet is linked when the site asks for a file"
    link = css_select("head link[rel=stylesheet][data-turbo-track=reload]")
    assert_equal 1, link.size
    assert_includes link_header, "<#{link.first["href"]}>; rel=preload; as=style"

    site.update!(stylesheet_mode: "inline")
    Theme::Stylesheet.with_limit(1) { get "/about" }
    assert_response :success
    assert_empty css_select("link[rel=stylesheet]"), "a stylesheet over the limit is drawn in when the site asks for it in the page"
    assert_not_includes link_header, "theme"
    assert_equal built.compiled_content.force_encoding(Encoding::UTF_8), drawn_style.first.text

    site.update!(stylesheet_mode: "automatic")
    Theme::Stylesheet.with_limit(1) { get "/about" }
    assert_empty drawn_style, "Automatic links a stylesheet over the limit"
    get "/about"
    assert_equal 1, drawn_style.size, "Automatic draws in one under it"
  end

  # The settings row is a key of the public ETag, so a changed mode is a new
  # page at the visitor's next request, never a 304 of the old head; a
  # shared cache in front, which keys on the address, takes the new page
  # once its `s-maxage` is spent and it asks again with the old ETag.
  test "a change of the mode changes the ETag, so the next page has the new head" do
    get "/about"
    etag = response.headers["ETag"]
    get "/about", headers: { "If-None-Match" => etag }
    assert_response :not_modified

    Settings::Save.call(site_settings(:default), attributes: { stylesheet_mode: "file" }, actor: users(:one))
    get "/about", headers: { "If-None-Match" => etag }
    assert_response :success
    assert_not_equal etag, response.headers["ETag"]
    assert_empty drawn_style
    assert_equal 1, css_select("head link[rel=stylesheet]").size
  end

  test "a stylesheet that would change by being drawn in is linked: a relative address, an import, or the end of the style element in its text" do
    [ %(.a{background:url("mark.svg")}), %(.a{src:url(font.woff2)}), %(@import "more.css";.a{}), %(.a::after{content:"</style>"}), %(.a::after{content:"</STYLE"}) ].each do |css|
      ThemeCss::MODES.each { |mode| assert_not stylesheet_of(css, digest: "x").inline?(mode), "#{mode}: #{css}" }
    end
    [ %(.a{background:url("/assets/mark-1a2b3c4d.svg")}), %(.a{background:url(data:image/png;base64,AA)}), %(.a{mask:url(#m)}), %(@import url("https://fonts.example/a.css");.a{}), %(.a>.b{content:"<p>"}) ].each do |css|
      assert stylesheet_of(css, digest: "x").inline?("automatic"), css
    end
  end

  test "another stylesheet changes the ETag and the CSS drawn in, so a page is never confirmed with the old styles" do
    first = stylesheet_of(".first{color:red}", digest: "aaaaaaaa")
    second = stylesheet_of(".second{color:blue}", digest: "bbbbbbbb")

    with_singleton_override(Theme::Stylesheet, :current, -> { first }) { get "/about" }
    assert_response :success
    etag = response.headers["ETag"]
    assert_equal ".first{color:red}", drawn_style.first.text

    with_singleton_override(Theme::Stylesheet, :current, -> { first }) { get "/about", headers: { "If-None-Match" => etag } }
    assert_response :not_modified

    with_singleton_override(Theme::Stylesheet, :current, -> { second }) { get "/about", headers: { "If-None-Match" => etag } }
    assert_response :success
    assert_not_equal etag, response.headers["ETag"]
    assert_equal ".second{color:blue}", drawn_style.first.text
  end

  test "a theme changes the ETag of a page whose stylesheet is drawn in" do
    get "/about"
    etag = response.headers["ETag"]
    with_plain_theme { get "/about", headers: { "If-None-Match" => etag } }
    assert_response :success
    assert_equal 1, drawn_style.size
  end

  test "the policy allows the style element: no style-src is set, and with a nonce generator the style carries the request's nonce, as the inline script does" do
    get "/about"
    policy = response.headers["Content-Security-Policy"].to_s
    assert_not_includes policy, "style-src"
    assert_not_includes policy, "default-src"
    assert_nil drawn_style.first["nonce"]

    config = Rails.application.env_config
    key = "action_dispatch.content_security_policy_nonce_generator"
    before = config[key]
    begin
      config[key] = ->(_request) { "n0nce" }
      get "/about"
    ensure
      config[key] = before
    end
    assert_equal "n0nce", drawn_style.first["nonce"]
    assert_equal "n0nce", css_select("head script:not([type])").first["nonce"]
  end

  test "a theme's head that preloads its fonts and prints a style of its own leaves the CMS's stylesheet in place, once and after it" do
    with_theme_copy do |dir|
      dir.join("views/layouts/public/_head.html.erb").write(<<~ERB)
        <link rel="preload" href="/assets/plain-sans.woff2" as="font" type="font/woff2" crossorigin>
        <style>.theme-own{color:red}</style>
      ERB
      Theme.with(Theme.load(ThemeFolder.new(dir))) { get "/about" }
    end

    assert_response :success
    styles = css_select("head style")
    assert_equal [ ".theme-own{color:red}", built.compiled_content.force_encoding(Encoding::UTF_8) ], styles.map(&:text)
    assert_equal "reload", styles.last["data-turbo-track"]
    assert_equal 1, css_select("head link[rel=preload][as=font]").size
  end

  test "the stylesheet is read once per digest, and read again when the built file changes" do
    first = Theme::Stylesheet.current
    assert_same first, Theme::Stylesheet.current

    changed = FakeAsset.new(digest: "cccccccc", content: ".c{}", compiled_content: ".c{}")
    with_singleton_override(Rails.application.assets.load_path, :find, ->(_name) { changed }) do
      assert_equal ".c{}", Theme::Stylesheet.current.css
      assert_same Theme::Stylesheet.current, Theme::Stylesheet.current
    end
    assert_equal first.digest, Theme::Stylesheet.current.digest
  end
end
