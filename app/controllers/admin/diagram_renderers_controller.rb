module Admin
  # The Diagram block's renderer frame, `GET <admin>/diagram-renderer`: the one
  # document Mermaid runs in. The block card frames it with
  # `sandbox="allow-scripts"`, and its own policy says `sandbox allow-scripts`
  # again, so its origin is opaque however it is opened: it cannot read CS
  # Studio's cookies, storage or DOM, send a request or navigate anything. A
  # parser bug in Mermaid lands there and not in CS Studio's page.
  #
  # It holds no data and is the same document for everyone who may open CS
  # Studio: no layout (no CSRF meta, no name, no flash read), and the frame
  # learns everything it draws from the card's messages. The line rules
  # (`Diagrams::Source.rules_json`), the drawing's limits and the font files'
  # addresses are written into it as JSON for `public/diagram-renderer.js`.
  #
  # Both scripts are classic scripts, Mermaid's IIFE build by its asset URL
  # and the frame's own script from public/: a document at an opaque origin
  # cannot load the app's module scripts without CORS.
  class DiagramRenderersController < BaseController
    # The policy as a whole, not the application's with additions: nothing of
    # the global one (frames, objects) applies to a document that frames
    # nothing, and `connect-src 'none'` with `form-action 'none'` leave it no
    # way to send what it draws anywhere but to its parent.
    POLICY = ActionDispatch::ContentSecurityPolicy.new do |policy|
      policy.sandbox "allow-scripts"
      policy.default_src :none
      policy.script_src :self
      # Mermaid writes a <style> into the drawing, and the frame paints with its own.
      policy.style_src :self, :unsafe_inline
      policy.font_src :self
      policy.connect_src :none
      policy.form_action :none
    end

    # The most a drawing may hold after cleaning: the frame refuses a larger
    # one as too large instead of handing it back, so a save is never left
    # for the server's sanitizer to refuse.
    LIMITS = { max_bytes: Diagrams::Drawing::MAX_BYTES, max_elements: Diagrams::Drawing::MAX_ELEMENTS }.freeze

    SCRIPT = "diagram-renderer.js".freeze

    # The default theme's tokens, where the diagram's are defined.
    TOKENS = Rails.root.join(ThemeCss::DEFAULT).dirname.join("tokens.css")

    # What the frame paints the drawing it shows with: the Diagram block's
    # public stylesheet, whole (plain CSS by design, so one file paints the
    # editor's drawing and the site's), after the diagram's tokens as the
    # default theme's light values. Those stand until the card posts CS
    # Studio's colours, which the frame sets on its root and which win. A
    # token's `var()` of a base token is written as the base's value, from
    # the same tokens.css, since the frame defines no base token. Read once
    # per process.
    def self.paint
      @paint ||= begin
        type = BlockTypes.fetch(:diagram)
        css = type.stylesheet_path.read
        raise "#{type.stylesheet_path} holds `</`, which would end the frame's <style>" if css.include?("</")

        names = (type.themed_tokens + type.fixed_tokens).map { |name| "--th-#{name}" }
        defaults = names.map { |name| "  #{name}: #{light_value(name)};" }.join("\n")
        ":root {\n#{defaults}\n}\n#{css}".freeze
      end
    end

    # A token's light value with every `var(--th-…)` in it written out:
    # the light block of tokens.css, then its fixed block.
    def self.light_value(name, depth = 0)
      raise "#{name}: var() nested too deep in #{TOKENS.basename}" if depth > 8

      @light_tokens ||= begin
        text = TOKENS.read
        [ text[/:root, \[data-theme="light"\]\s*\{(.*?)\}/m, 1], text[/^:root \{(.*?)\}/m, 1] ]
          .map { |block| block.to_s.gsub(%r{/\*.*?\*/}m, "").scan(/(--th-[\w-]+):\s*([^;]+);/).to_h }.reduce(:merge)
      end
      value = @light_tokens.fetch(name) { raise "#{name} is not defined in #{TOKENS.basename}" }
      value.gsub(/var\((--th-[\w-]+)\)/) { light_value(Regexp.last_match(1), depth + 1) }.strip
    end

    layout false

    before_action { request.content_security_policy = POLICY }

    def show
      @frame = {
        limits: LIMITS,
        fonts: ContentSpiel::DiagramFontCors::WEIGHTS.map { |weight| { weight: weight, url: helpers.asset_path("archivo-latin-#{weight}-normal.woff2") } }
      }
      @script_url = script_url
    end

    private

    # A file in public/ has no digest and is cached for a year
    # (`public_file_server.headers`), so its address carries the file's own:
    # the frame never runs a script older than the page that framed it. Read
    # on each request, so an edit in development is seen at once.
    def script_url
      "/#{SCRIPT}?v=#{Digest::SHA256.file(Rails.public_path.join(SCRIPT)).hexdigest.first(16)}"
    end
  end
end
