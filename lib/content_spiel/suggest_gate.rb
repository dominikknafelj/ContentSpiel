require "json"
require "stringio"

# The body of `POST /search/suggestions` (search 2 spec §4.1), read before
# Rails reads it. Inserted after `Rails::Rack::Logger` (`config/application.rb`):
# after the request line, which names the path and never the body, and
# before anything parses the body.
#
# WHY A MIDDLEWARE AND NOT THE CONTROLLER: Rails parses a JSON body the
# moment anything asks for the parameters, and the controller's
# instrumentation asks before the first callback runs (the "Parameters:"
# line). A body that does not parse raises a `JSON::ParserError` whose
# message quotes the body, which the error's log line then prints: a
# visitor's typed prefix in the log. So here, and only for this one path
# and verb:
#
# - a `Content-Length` over `MAX_BODY` is answered 413 with nothing read;
#   a body with no length (chunked) is read through `MAX_BODY + 1` bytes at
#   most, and over `MAX_BODY` is a 413 too. The 413 is answered here, the
#   controller's empty answer with its headers (`REFUSED`, `HEADERS`), and
#   is recorded on the request's span as `search.outcome` `refused`;
# - the bytes read are parsed with `JSON.parse`, and `ENV_KEY` holds the
#   parsed value, or `:malformed` for a body that does not parse, whose
#   error is rescued without its message being read;
# - `rack.input` becomes the bytes read, with their length, so Rails never
#   reads past them; a malformed body becomes `{}`, the content type kept,
#   so Rails parses only `{}`, the controller's type check still runs first
#   and its 400 is answered from the flag.
#
# NO ETAG: `Rack::ETag`, which stands inside this, writes a digest of every
# 200's body; an answer that no cache stores (`Cache-Control: private,
# no-store`) is never revalidated, so its digest is taken off on the way out.
#
# THE PATH IS THE ROUTER'S: it is compared after
# `ActionDispatch::Journey::Router::Utils.normalize_path`, so a trailing or
# doubled slash, which the router still routes to the controller, is gated
# too. On the admin host (`ADMIN_HOST`, `SiteAddress.admin`) the route does
# not answer (`HostRouteConstraint::Site`), so the gate leaves the request
# to the router's 404.
#
# In lib/ and required from config/application.rb, which inserts it while
# the application is configured, before autoloading is set up.
module ContentSpiel
  class SuggestGate
    PATH = "/search/suggestions".freeze
    MAX_BODY = 1_024
    ENV_KEY = "content_spiel.suggest.body".freeze

    REFUSED = { state: "refused", status: "", suggestions: [] }.to_json.freeze
    HEADERS = { "content-type" => "application/json; charset=utf-8", "cache-control" => "private, no-store", "x-robots-tag" => "noindex" }.freeze

    def initialize(app)
      @app = app
    end

    def call(env)
      request = Rack::Request.new(env)
      return @app.call(env) unless gated?(request)

      bytes = body_of(request)
      return too_large if bytes.nil?

      value = parsed(bytes)
      handed = value == :malformed ? "{}".b : bytes
      request.set_header(ENV_KEY, value)
      request.set_header(Rack::RACK_INPUT, StringIO.new(handed))
      request.set_header("CONTENT_LENGTH", handed.bytesize.to_s)
      request.delete_header("HTTP_TRANSFER_ENCODING")
      status, headers, body = @app.call(env)
      headers.delete("etag")
      [ status, headers, body ]
    end

    private

    def gated?(request)
      return false unless request.post?
      return false unless ActionDispatch::Journey::Router::Utils.normalize_path(request.path_info.to_s) == PATH

      admin = SiteAddress.admin
      !admin.configured? || !request.host.to_s.casecmp?(admin.host)
    end

    # The body's bytes, or nil when it is over `MAX_BODY`.
    def body_of(request)
      return nil if request.content_length.to_i > MAX_BODY

      input = request.body
      bytes = input ? input.read(MAX_BODY + 1).to_s.b : "".b
      bytes.bytesize > MAX_BODY ? nil : bytes
    end

    def parsed(bytes)
      JSON.parse(bytes.dup.force_encoding(Encoding::UTF_8))
    rescue JSON::ParserError, EncodingError
      :malformed
    end

    def too_large
      Telemetry.record(OpenTelemetry::Trace.current_span, "search.outcome" => "refused")
      [ 413, HEADERS.dup, [ REFUSED ] ]
    end
  end
end
