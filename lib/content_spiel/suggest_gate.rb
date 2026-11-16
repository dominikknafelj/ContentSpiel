require "json"
require "stringio"

# The body of `POST /search/suggestions` (search 2 spec §4.1), read before
# Rails reads it. Inserted after `Rails::Rack::Logger` (`config/application.rb`):
# after the request line, which names the path and never the body, and
# before anything parses the body.
#
# WHY A MIDDLEWARE AND NOT THE CONTROLLER: Rails parses a body the moment
# anything asks for the parameters, and the controller's instrumentation
# asks before the first callback runs (the "Parameters:" line). Whatever
# Rails parses is in that line, and a parse that fails raises an error whose
# message quotes the value: a JSON string or a form field with a byte that
# is no UTF-8 ("Invalid encoding for parameter: …"), at info. So Rails is
# handed NOTHING of this body, and here, for this one path and verb alone:
#
# - a `Content-Length` over `MAX_BODY` is answered 413 with nothing read
#   by Rails or the gate; a body with no length (chunked) is read through
#   `MAX_BODY + 1` bytes at most, and over `MAX_BODY` is a 413 too. What
#   this caps is what Rails parses and logs, not the process's memory:
#   Puma has buffered the whole body (in memory, or a temporary file past
#   its threshold) before any middleware runs, as for every route, and a
#   cap on that is the front proxy's (`docs/reference/hosting.md`). The 413 is answered here, the
#   controller's empty answer with its headers (`REFUSED`, `HEADERS`), and
#   is recorded on the request's span as `search.outcome` `refused`;
# - the bytes read are parsed with `JSON.parse` when they are UTF-8 (RFC
#   8259: JSON text is), and `ENV_KEY` holds the parsed value, or
#   `:malformed` for bytes that are no UTF-8 or do not parse, whose error is
#   rescued without its message being read;
# - `rack.input` becomes empty, with a length of 0, whatever the body and
#   its type: Rails then parses no parameter from it (a key of the visitor's
#   own, a nested value, a form field, a multipart part), so none is in a
#   log line or an error; what Rack kept of a form body it parsed before
#   this is forgotten (`FORM_CACHE`). The content type is kept, so the controller's
#   type check still answers first, and its 400 is answered from the flag.
#   The controller reads the body from `ENV_KEY` alone.
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

    # What Rack keeps of a form body it parsed, the error of a failed parse
    # included, which it raises again, message and all, at Rails' next read.
    # `Rack::MethodOverride` stands before this and parses a form POST's
    # body for `_method`, so a form field that is no UTF-8 would otherwise
    # come back as Rails' `BadRequest` quoting it.
    FORM_CACHE = [ Rack::RACK_REQUEST_FORM_INPUT, Rack::RACK_REQUEST_FORM_HASH, Rack::RACK_REQUEST_FORM_PAIRS,
                   Rack::RACK_REQUEST_FORM_VARS, Rack::RACK_REQUEST_FORM_ERROR ].freeze

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

      request.set_header(ENV_KEY, parsed(bytes))
      request.set_header(Rack::RACK_INPUT, StringIO.new("".b))
      request.set_header("CONTENT_LENGTH", "0")
      FORM_CACHE.each { |key| request.delete_header(key) }
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
      text = bytes.dup.force_encoding(Encoding::UTF_8)
      return :malformed unless text.valid_encoding?

      JSON.parse(text)
    rescue JSON::ParserError, EncodingError
      :malformed
    end

    def too_large
      Telemetry.record(OpenTelemetry::Trace.current_span, "search.outcome" => "refused")
      [ 413, HEADERS.dup, [ REFUSED ] ]
    end
  end
end
