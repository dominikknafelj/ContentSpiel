require "test_helper"

# The Diagram block's renderer frame: the one document Mermaid runs in, at an
# opaque origin (`sandbox allow-scripts` in its own header and on the
# element). It holds no data and is the same for everyone who may open CS
# Studio, so nothing in it can be read out of the sandbox but the drawing.
class Admin::DiagramRenderersControllerTest < ActionDispatch::IntegrationTest
  FRAME_POLICY = "sandbox allow-scripts; default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; " \
    "font-src 'self'; connect-src 'none'; form-action 'none'".freeze

  setup { site_settings(:default).update!(setup_completed_at: Time.current) }

  test "the renderer answers the same document to everyone who may open CS Studio, with the frame's CSP exactly" do
    bodies = %i[one reader].map do |name|
      sign_in_as(users(name))
      get admin_diagram_renderer_path
      assert_response :ok
      assert_equal FRAME_POLICY, response.headers["Content-Security-Policy"]
      response.body
    end

    assert_equal bodies.first, bodies.last
  end

  test "the renderer is behind sign-in" do
    get admin_diagram_renderer_path

    assert_redirected_to admin_sign_in_path
  end

  test "the renderer holds no data: no CSRF meta, no user name, no cookie set" do
    user = users(:one)
    user.update!(name: "Ada Lovelace")
    sign_in_as(user)

    get admin_diagram_renderer_path

    assert_response :ok
    assert_no_match(/csrf/i, response.body)
    assert_no_match(/Ada Lovelace|#{Regexp.escape(user.email_address)}/, response.body)
    assert_nil response.headers["Set-Cookie"]
    assert_select "meta[name=?]", "csrf-token", count: 0
    assert_select "form", count: 0
  end

  test "the renderer is not on a public host when ADMIN_HOST is set" do
    with_site_address("https://docs.example.org") do
      with_admin_address("https://studio.example.internal") do
        https!
        host! "studio.example.internal"
        sign_in_as(users(:one))
        get admin_diagram_renderer_path
        assert_response :ok
        assert_equal FRAME_POLICY, response.headers["Content-Security-Policy"]

        host! "docs.example.org"
        get admin_diagram_renderer_path
        assert_response :not_found
        assert_nil response.location
      end
    end
  end

  test "the renderer's markup carries the rules as JSON and the Mermaid file's asset URL" do
    sign_in_as(users(:one))

    get admin_diagram_renderer_path

    rules = css_select("script#diagram-rules[type='application/json']").first
    assert rules, "no rules JSON"
    assert_equal JSON.parse(Diagrams::Source.rules_json), JSON.parse(rules.text)

    frame = JSON.parse(css_select("script#diagram-frame[type='application/json']").first.text)
    assert_equal({ "max_bytes" => Diagrams::Drawing::MAX_BYTES, "max_elements" => Diagrams::Drawing::MAX_ELEMENTS }, frame["limits"])
    assert_equal %w[400 500 600 700], frame["fonts"].map { |font| font["weight"] }
    frame["fonts"].each do |font|
      assert_equal helpers.asset_path("archivo-latin-#{font["weight"]}-normal.woff2"), font["url"]
    end

    scripts = css_select("script[src]").map { |script| script["src"] }
    assert_equal helpers.asset_path("mermaid.js"), scripts.first
    assert_match %r{\A/diagram-renderer\.js\?v=\h{16}\z}, scripts.last
    assert_equal 2, scripts.size
    assert css_select("script[src]").none? { |script| script["type"] == "module" }, "the frame's scripts are classic scripts"
    assert_select "style#diagram-paint", count: 1
  end

  # The frame paints the drawing it shows with the public stylesheet itself,
  # inlined, and, until the card posts CS Studio's colours, with the default
  # theme's light values of the diagram's tokens, read from tokens.css.
  test "the frame's style holds diagram.css as it is, and the diagram's tokens as the default theme's light values" do
    sign_in_as(users(:one))

    get admin_diagram_renderer_path

    style = css_select("style#diagram-paint").first.text
    assert_includes style, BlockTypes.fetch(:diagram).stylesheet_path.read, "the file's text, whole"
    assert_select "#diagram.content-block--diagram", count: 1, text: ""
    defaults = style[/:root \{(.*?)\}/m, 1] or flunk("no :root rule of defaults")
    values = defaults.scan(/(--th-[\w-]+):\s*([^;]+);/).to_h
    tokens = BlockTypes.fetch(:diagram).then { |type| (type.themed_tokens + type.fixed_tokens).map { |name| "--th-#{name}" } }
    assert_equal tokens.sort, values.keys.sort
    assert_equal "#141417", values["--th-diagram-ink"], "--th-ink's light value, not a var() the frame cannot resolve"
    assert_equal "color-mix(in srgb, oklch(0.95 0.025 250) 60%, #ffffff)", values["--th-diagram-note"]
    assert_match(/\A"Archivo"/, values["--th-diagram-font"])
    values.each_value { |value| assert_no_match(/var\(/, value) }
  end

  test "an Archivo font file answers Access-Control-Allow-Origin: *" do
    %w[400 500 600 700].each do |weight|
      get helpers.asset_path("archivo-latin-#{weight}-normal.woff2")
      assert_response :ok
      assert_equal "*", response.headers["Access-Control-Allow-Origin"], weight
    end

    get helpers.asset_path("ibm-plex-mono-latin-400-normal.woff2")
    assert_response :ok
    assert_nil response.headers["Access-Control-Allow-Origin"], "only the frame's four faces are shared"

    get helpers.asset_path("mermaid.js")
    assert_response :ok
    assert_nil response.headers["Access-Control-Allow-Origin"]
  end

  test "no public page and no CS Studio screen without a Diagram block references mermaid" do
    Page.create!(title: "Home", slug: "", published_at: 1.day.ago)

    get "/"
    assert_response :ok
    assert_names_no_mermaid "the public home"

    sign_in_as(users(:one))
    get admin_root_path
    assert_response :ok
    assert_names_no_mermaid "the dashboard"
  end

  private

  def helpers = ActionController::Base.helpers

  # The import map is one lookup table on every page and maps `mermaid` (the
  # pin is there for `bin/importmap audit`); a mapping is fetched only when
  # something imports it. Everything else of the page must not name it: no
  # modulepreload, no script, no entry point's import, no frame.
  def assert_names_no_mermaid(what)
    document = Nokogiri::HTML5(response.body)
    importmap = document.at_css("script[type=importmap]")
    assert_match(/"mermaid":/, importmap.text, "the import map no longer maps mermaid")
    importmap.remove
    assert_no_match(/mermaid|diagram-renderer/, document.to_html, "#{what} names Mermaid or the renderer")
  end
end
