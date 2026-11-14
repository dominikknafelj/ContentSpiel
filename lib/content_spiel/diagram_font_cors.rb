# `Access-Control-Allow-Origin: *` on the four Archivo faces the Diagram
# block's renderer frame draws with, and on no other file.
#
# The frame (`Admin::DiagramRenderersController`) is sandboxed without
# `allow-same-origin`, so its origin is opaque: a font it loads with
# `FontFace` is a CORS request sent with `Origin: null`, and without this
# header `FontFace.load()` fails, Mermaid measures its labels in a fallback
# face and the boxes no longer fit the Archivo a page paints them in.
# `font-src 'self'` in the frame's policy is not enough on its own. The faces
# are public files (the default theme's stylesheet names them on every page),
# so sharing them with any origin discloses nothing.
#
# The path is matched with or without its digest: in development and test
# Propshaft serves `app/assets/fonts` itself (`Propshaft::Server`), in
# production `assets:precompile` writes them to `public/assets` and
# `ActionDispatch::Static` serves them, behind Thruster. This middleware
# stands before both (`config/application.rb`), so the header is on the
# answer whichever of them gives it.
#
# In lib/ and required from config/application.rb, which inserts it while
# the application is configured, before autoloading is set up.
module ContentSpiel
  class DiagramFontCors
    WEIGHTS = %w[400 500 600 700].freeze

    def initialize(app, prefix:)
      @app = app
      @pattern = %r{\A#{Regexp.escape(prefix)}/archivo-latin-(?:#{WEIGHTS.join("|")})-normal(?:-[0-9a-zA-Z]{7,128})?\.woff2\z}
    end

    def call(env)
      status, headers, body = @app.call(env)
      headers["access-control-allow-origin"] = "*" if @pattern.match?(Rack::Request.new(env).path_info.to_s)
      [ status, headers, body ]
    end
  end
end
