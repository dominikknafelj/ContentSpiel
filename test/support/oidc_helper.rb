require "socket"

# A fake OpenID Connect provider on 127.0.0.1, so no test of single sign-on
# reaches the network.
#
# `with_fake_idp(email:, email_verified:, subject:, name:, refresh_token:,
# offline_access:, required:) { |idp| … }` starts a TCPServer on 127.0.0.1
# and an ephemeral port, whose issuer is `http://127.0.0.1:<port>/idp` (an
# http issuer is allowed to 127.0.0.1 outside production,
# `SignIn::Oidc::Provider#check_issuer!`), sets the four SSO_* variables to
# it (and SSO_REQUIRED=1 with `required: true`) through `with_sign_in_env`,
# and puts them back after.
#
# THE CACHE. The test environment's `Rails.cache` is a `:null_store`, under
# which "discovery is read once, then cached for an hour" could not be seen:
# the block runs with `Rails.cache` swapped for a fresh MemoryStore, and the
# old store is put back after. So no discovery or keys entry outlives the
# block, and none is there before it.
#
# ONE SOCKET FOR EVERY PART. The server answers:
#
#   GET  /idp/.well-known/openid-configuration  the discovery document
#   GET  /idp/keys                                the key set
#   GET  /idp/authorize                           a 302 to the redirect_uri
#                                                 with `code` and `state`
#                                                 (`error=access_denied`
#                                                 after `deny!`)
#   POST /idp/token                               the code and refresh grants
#
# A browser test follows the authorization redirect for real: headless
# Chrome runs on this machine, so it opens 127.0.0.1:<port> itself and is
# sent back to the Capybara server's callback. An integration test, which
# cannot leave the application, takes the same redirect with
# `idp.authorize(url)` (a GET to the socket, answering the Location) and
# `get`s the callback it names.
#
# Each connection is answered on a thread of its own and closed after one
# request, so a browser's idle preconnect never holds the next request
# behind it.
#
# THE TOKENS are signed by an RSA key made once per process (`IDP_KEY`),
# served at /idp/keys under its thumbprint as `kid`. `id_token(claims, alg:,
# key:)` mints any token a test needs: `alg: "none"`, `key: :unknown` (a
# key the key set never serves), a wrong `aud` or `iss`, or an `exp` in the
# past, each by naming the claim.
#
# The `idp` object:
#
# - `requests`: every request seen, recorded before it is answered (`method`,
#   `path`, `params`: the query of a GET, the form of a POST, and `headers`);
# - `code_for(nonce:)`: a code the token endpoint answers once with an ID
#   token carrying that nonce;
# - `answer_token_with(status:, body:)` and `answer_discovery_with(status:,
#   body:)`: the next answer of that endpoint, once (a Hash is sent as JSON,
#   a String as it is);
# - `rotate_refresh_token(to)`: the next refresh answers `to`, which is then
#   the token a refresh must send;
# - `change_identity(**)`: what the next ID tokens say (`subject: "sub-2"`
#   for a refresh that names somebody else);
# - `revoke!`: every refresh from now on answers 400 `invalid_grant`;
# - `down!`: the socket is closed, so a connection is refused;
# - `deny!`: the authorization endpoint answers `error=access_denied`;
# - `sign_with_unknown_key!`: the ID tokens are signed by a key the key set
#   never serves; `rotate_keys!`: by a new key, which the key set serves
#   beside the old one from now on (a provider's key rotation).
module OidcHelper
  IDP_KEY = OpenSSL::PKey::RSA.generate(2048)
  OTHER_KEY = OpenSSL::PKey::RSA.generate(2048)
  UNKNOWN_KEY = OpenSSL::PKey::RSA.generate(2048)

  CLIENT_ID = "content-spiel-test-client".freeze
  CLIENT_SECRET = "fake-idp-client-secret-0f3a9c".freeze
  NAME = "Example ID".freeze

  def with_fake_idp(email: "reader@example.com", email_verified: true, subject: "sub-1", name: "Rea Der",
    refresh_token: "rt-1", offline_access: true, required: false)
    idp = FakeIdp.new(email: email, email_verified: email_verified, subject: subject, name: name,
      refresh_token: refresh_token, offline_access: offline_access)
    cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    env = {
      "SSO_ISSUER" => idp.issuer, "SSO_CLIENT_ID" => CLIENT_ID, "SSO_CLIENT_SECRET" => CLIENT_SECRET,
      "SSO_NAME" => NAME, "SSO_REQUIRED" => required ? "1" : nil
    }
    with_sign_in_env(env) { yield idp }
  ensure
    idp&.stop
    Rails.cache = cache if cache
  end

  class FakeIdp
    Request = Data.define(:method, :path, :params, :headers)

    # Seconds a killed thread is given to finish its `ensure`.
    JOIN_WAIT = 1

    STATUS_WORDS = { 200 => "OK", 302 => "Found", 400 => "Bad Request", 401 => "Unauthorized", 404 => "Not Found", 500 => "Internal Server Error" }.freeze

    attr_reader :issuer, :requests

    def initialize(email:, email_verified:, subject:, name:, refresh_token:, offline_access:)
      @identity = { "sub" => subject, "email" => email, "email_verified" => email_verified, "name" => name }
      @refresh_token = refresh_token
      @offline_access = offline_access
      @requests = []
      @codes = {}
      @answers = {}
      @lock = Mutex.new
      @signing_key = IDP_KEY
      @served_keys = [ IDP_KEY ]
      @server = TCPServer.new("127.0.0.1", 0)
      @issuer = "http://127.0.0.1:#{@server.addr[1]}/idp"
      @workers = []
      @acceptor = Thread.new { accept_loop }
      @acceptor.report_on_exception = false
    end

    def provider = SignIn::Oidc::Provider.current
    def client_id = CLIENT_ID
    def name = NAME
    def public_key = IDP_KEY.public_key
    def key_id = JSON::JWK.new(IDP_KEY.public_key)[:kid]

    def discovery_document
      {
        "issuer" => issuer,
        "authorization_endpoint" => "#{issuer}/authorize",
        "token_endpoint" => "#{issuer}/token",
        "jwks_uri" => "#{issuer}/keys",
        "response_types_supported" => [ "code" ],
        "subject_types_supported" => [ "public" ],
        "id_token_signing_alg_values_supported" => [ "RS256" ],
        "scopes_supported" => [ "openid", "email", "profile", *("offline_access" if @offline_access) ],
        "code_challenge_methods_supported" => [ "S256" ]
      }
    end

    def code_for(nonce:, challenge: nil, redirect_uri: nil)
      SecureRandom.urlsafe_base64(24).tap do |code|
        @lock.synchronize { @codes[code] = { nonce: nonce, challenge: challenge, redirect_uri: redirect_uri } }
      end
    end

    # A signed ID token for the current identity, `claims` merged over it
    # (a nil value drops the claim). `key:` is :idp (served) or :unknown
    # (never served); `alg: "none"` is an unsigned token.
    def id_token(claims = {}, alg: "RS256", key: :idp)
      now = Time.current.to_i
      payload = @identity.merge("iss" => issuer, "aud" => CLIENT_ID, "iat" => now, "exp" => now + 300)
        .merge(claims.stringify_keys).compact
      jwt = JSON::JWT.new(payload)
      return jwt.to_s if alg == "none"

      signer = { idp: @signing_key, unknown: UNKNOWN_KEY }.fetch(key)
      jwt.sign(JSON::JWK.new(signer), alg.to_sym).to_s
    end

    def answer_token_with(status: 200, body:) = @lock.synchronize { @answers["/idp/token"] = [ status, body ] }
    def answer_discovery_with(status: 200, body:) = @lock.synchronize { @answers["/idp/.well-known/openid-configuration"] = [ status, body ] }

    def rotate_refresh_token(to) = @lock.synchronize { @next_refresh_token = to }
    def change_identity(subject: @identity["sub"], email: @identity["email"], email_verified: @identity["email_verified"], name: @identity["name"])
      @lock.synchronize { @identity = { "sub" => subject, "email" => email, "email_verified" => email_verified, "name" => name } }
    end

    def revoke! = @lock.synchronize { @revoked = true }
    def deny! = @lock.synchronize { @denied = true }
    def sign_with_unknown_key! = @lock.synchronize { @signing_key = UNKNOWN_KEY }

    def rotate_keys!
      @lock.synchronize do
        @signing_key = OTHER_KEY
        @served_keys = [ IDP_KEY, OTHER_KEY ]
      end
    end

    # The acceptor is joined after it is killed, so no worker is started
    # once this returns.
    def down!
      @acceptor.kill
      @acceptor.join(JOIN_WAIT)
      @server.close unless @server.closed?
    end

    def stop
      down!
      @lock.synchronize { @workers.dup }.each do |worker|
        worker.kill
        worker.join(JOIN_WAIT)
      end
    end

    # The authorization endpoint's answer to `url`, as a browser would be
    # sent: the Location of its 302.
    def authorize(url)
      uri = URI(url)
      response = Net::HTTP.get_response(uri)
      raise "the fake provider answered #{response.code} to the authorization request" unless response.code == "302"

      response["Location"]
    end

    # The token endpoint's answer to `form`, sent with the client's own
    # Basic credentials: [status, parsed body].
    def post_token(form)
      uri = URI("#{issuer}/token")
      request = Net::HTTP::Post.new(uri)
      request.basic_auth(CLIENT_ID, CLIENT_SECRET)
      request.set_form_data(form)
      response = Net::HTTP.start(uri.host, uri.port) { |http| http.request(request) }
      [ response.code.to_i, JSON.parse(response.body) ]
    end

    private

    def accept_loop
      loop do
        client = @server.accept
        worker = Thread.new(client) { |socket| serve(socket) }
        worker.report_on_exception = false
        @lock.synchronize { @workers << worker }
      end
    end

    def serve(socket)
      line = socket.gets.to_s
      return if line.empty?

      method, target = line.split(" ", 3)
      headers = {}
      while (header = socket.gets) && header != "\r\n"
        key, value = header.chomp.split(": ", 2)
        headers[key.downcase] = value
      end
      uri = URI(target)
      length = headers["content-length"].to_i
      params = method == "POST" ? Rack::Utils.parse_query(length.positive? ? socket.read(length) : "") : Rack::Utils.parse_query(uri.query.to_s)
      request = Request.new(method: method, path: uri.path, params: params, headers: headers)
      @lock.synchronize { @requests << request }

      write(socket, *answer(request))
    rescue StandardError => error
      write(socket, 500, { "error" => error.class.name }) unless socket.closed?
    ensure
      socket.close unless socket.closed?
    end

    def answer(request)
      queued = @lock.synchronize { @answers.delete(request.path) }
      return queued if queued

      case [ request.method, request.path ]
      in [ "GET", "/idp/.well-known/openid-configuration" ] then [ 200, discovery_document ]
      in [ "GET", "/idp/keys" ] then [ 200, { "keys" => @served_keys.map { |key| JSON::JWK.new(key.public_key).as_json } } ]
      in [ "GET", "/idp/authorize" ] then authorization(request.params)
      in [ "POST", "/idp/token" ] then token(request)
      else [ 404, { "error" => "not_found" } ]
      end
    end

    def authorization(params)
      redirect_uri = params["redirect_uri"]
      return [ 400, { "error" => "invalid_request" } ] unless params["client_id"] == CLIENT_ID && params["response_type"] == "code" && redirect_uri.present?

      back = if @denied
        { "error" => "access_denied", "state" => params["state"] }
      else
        { "code" => code_for(nonce: params["nonce"], challenge: params["code_challenge"], redirect_uri: redirect_uri), "state" => params["state"] }
      end
      separator = redirect_uri.include?("?") ? "&" : "?"
      [ 302, "", { "Location" => "#{redirect_uri}#{separator}#{back.compact.to_query}" } ]
    end

    def token(request)
      return [ 401, { "error" => "invalid_client" } ] unless client_authenticated?(request)

      case request.params["grant_type"]
      when "authorization_code" then code_grant(request.params)
      when "refresh_token" then refresh_grant(request.params)
      else [ 400, { "error" => "unsupported_grant_type" } ]
      end
    end

    # client_secret_basic (the default the discovery document implies), or
    # client_secret_post.
    def client_authenticated?(request)
      basic = request.headers["authorization"].to_s
      if basic.start_with?("Basic ")
        id, secret = Base64.decode64(basic.delete_prefix("Basic ")).split(":", 2).map { |part| CGI.unescape(part.to_s) }
        id == CLIENT_ID && secret == CLIENT_SECRET
      else
        request.params["client_id"] == CLIENT_ID && request.params["client_secret"] == CLIENT_SECRET
      end
    end

    # A code is spent by the exchange that it answers; a verifier that does
    # not match the challenge, or another redirect URI, is refused and leaves
    # it for the right one.
    def code_grant(params)
      @lock.synchronize do
        bound = @codes[params["code"]]
        return [ 400, { "error" => "invalid_grant" } ] unless bound
        if bound[:challenge] && Base64.urlsafe_encode64(Digest::SHA256.digest(params["code_verifier"].to_s), padding: false) != bound[:challenge]
          return [ 400, { "error" => "invalid_grant" } ]
        end
        return [ 400, { "error" => "invalid_grant" } ] if bound[:redirect_uri] && bound[:redirect_uri] != params["redirect_uri"]

        @codes.delete(params["code"])
        [ 200, tokens(nonce: bound[:nonce], refresh_token: (@refresh_token if @offline_access)) ]
      end
    end

    def refresh_grant(params)
      @lock.synchronize do
        return [ 400, { "error" => "invalid_grant" } ] if @revoked || @refresh_token.nil? || params["refresh_token"] != @refresh_token

        rotated = @next_refresh_token
        @refresh_token = rotated if rotated
        @next_refresh_token = nil
        [ 200, tokens(nonce: nil, refresh_token: rotated) ]
      end
    end

    def tokens(nonce:, refresh_token:)
      {
        "access_token" => SecureRandom.urlsafe_base64(24), "token_type" => "Bearer", "expires_in" => 3600,
        "id_token" => id_token({ "nonce" => nonce }), "refresh_token" => refresh_token
      }.compact
    end

    def write(socket, status, body, headers = {})
      text = body.is_a?(String) ? body : body.to_json
      type = body.is_a?(String) ? "text/plain" : "application/json"
      head = { "Content-Type" => type, "Content-Length" => text.bytesize, "Connection" => "close" }.merge(headers)
      socket.write("HTTP/1.1 #{status} #{STATUS_WORDS.fetch(status, "Status")}\r\n#{head.map { |key, value| "#{key}: #{value}\r\n" }.join}\r\n#{text}")
    end
  end
end
