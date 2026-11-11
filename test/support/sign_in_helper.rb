require "socket"

# The sign-in checks' outside calls, answered without the network.
#
# - `with_bot_check(answer) { … }`: Turnstile configured with Cloudflare's
#   documented always-pass test keys, and `SignIn::BotCheck.siteverify`
#   answering `:passed` (for `hostname`, an integration test's host unless
#   named, and the sign-in action), `:failed` or `:unavailable` (a refused
#   connection).
#   Each form it was sent is in `bot_check_requests`.
# - `with_leaked_password_check(leaked:, unavailable:) { … }`: the check
#   switched on (it is off in tests unless asked), and
#   `SignIn::LeakedPassword.range` answering as the service does, with the
#   suffixes of the `leaked` passwords at count 7 among padding and
#   unrelated lines; or, with `unavailable:` (an exception, or an Integer
#   status), failing so. Each prefix it was asked for is in
#   `leaked_password_requests`.
# - `with_http_stub(status:, body:) { |url, requests| … }`: a server on
#   127.0.0.1 and an ephemeral port that answers every request with the one
#   status and body, and records each request's line, headers and body, for
#   the tests of the HTTP call itself.
module SignInHelper
  # Cloudflare's test keys: public, and they pass every token.
  BOT_CHECK_KEYS = {
    "TURNSTILE_SITE_KEY" => "1x00000000000000000000AA",
    "TURNSTILE_SECRET_KEY" => "1x0000000000000000000000000000000AA"
  }.freeze

  BOT_CHECK_HOSTNAME = "www.example.com".freeze

  BOT_CHECK_ANSWERS = {
    passed: { "success" => true, "action" => SignIn::BotCheck::ACTION },
    failed: { "success" => false, "error-codes" => [ "invalid-input-response" ] }
  }.freeze

  # Lines of the range's answer that match no password a test types: a
  # padded one (count 0) and three listed ones.
  RANGE_PADDING = "0018A45C4D1DEF81644B54AB7F969B88D65:0".freeze
  RANGE_UNRELATED = %w[
    00D4F6E8FA6EECAD2A3AA415EEC418D38EC:2
    011053FD0102E94D6AE2F8B83D76FAF94F6:1
    012A7CA357541F0AC487871FEEC1891C49C:12
  ].freeze

  # One request the stub server received.
  StubRequest = Data.define(:line, :headers, :body)

  def bot_check_requests = (@bot_check_requests ||= [])

  def with_bot_check(answer = :passed, hostname: BOT_CHECK_HOSTNAME, &block)
    raise ArgumentError, "no bot check answer #{answer.inspect}" unless answer == :unavailable || BOT_CHECK_ANSWERS.key?(answer)

    requests = bot_check_requests
    siteverify = lambda do |form, url: nil|
      requests << form
      raise Errno::ECONNREFUSED if answer == :unavailable

      BOT_CHECK_ANSWERS.fetch(answer).merge("hostname" => hostname)
    end
    with_sign_in_env(BOT_CHECK_KEYS) { with_singleton_override(SignIn::BotCheck, :siteverify, siteverify, &block) }
  end

  def leaked_password_requests = (@leaked_password_requests ||= [])

  def with_leaked_password_check(leaked: [], unavailable: nil, &block)
    requests = leaked_password_requests
    digests = leaked.map { |password| Digest::SHA1.hexdigest(password).upcase }
    range = lambda do |prefix, url: nil|
      requests << prefix
      raise SignIn::LeakedPassword::Unavailable.status(unavailable) if unavailable.is_a?(Integer)
      raise unavailable if unavailable

      listed = digests.select { |digest| digest.start_with?(prefix) }.map { |digest| "#{digest[5..]}:7" }
      [ *RANGE_UNRELATED, RANGE_PADDING, *listed ].sort.join("\r\n")
    end
    with_sign_in_env("LEAKED_PASSWORD_CHECK" => "on") { with_singleton_override(SignIn::LeakedPassword, :range, range, &block) }
  end

  def with_http_stub(status: 200, body: "", content_type: "text/plain")
    server = TCPServer.new("127.0.0.1", 0)
    requests = []
    thread = Thread.new do
      Thread.current.report_on_exception = false
      loop do
        client = server.accept
        line = client.gets.to_s.chomp
        headers = {}
        while (header = client.gets) && header != "\r\n"
          name, value = header.chomp.split(": ", 2)
          headers[name.downcase] = value
        end
        length = headers["content-length"].to_i
        requests << StubRequest.new(line: line, headers: headers, body: length.positive? ? client.read(length) : "")
        client.write("HTTP/1.1 #{status} Stub\r\nContent-Type: #{content_type}\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
        client.close
      end
    end
    # A request is recorded before it is answered, so the list is whole
    # once the client has its answer.
    yield "http://127.0.0.1:#{server.addr[1]}", requests
  ensure
    thread&.kill
    server&.close
  end

  private

  # `values` in the environment for the block (nil deletes a name), each
  # name put back as it was afterwards.
  def with_sign_in_env(values)
    saved = values.keys.index_with { |name| ENV[name] }
    values.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
    yield
  ensure
    saved.each { |name, was| was.nil? ? ENV.delete(name) : ENV[name] = was }
  end
end
