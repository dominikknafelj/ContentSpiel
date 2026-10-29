require "test_helper"

# What a failed SMTP exchange is called (spec, "A failure's sentence"): a key
# by what was raised, the sentence for it, and the server's one reply line
# with the login replaced by "…" wherever it appears.
class MailFailureTest < ActiveSupport::TestCase
  USERNAME = "ana@example.test".freeze
  PASSWORD = "s3cret-Pa55".freeze

  def settings(username: USERNAME, password: PASSWORD)
    site = SiteSetting.instance.tap do |s|
      s.assign_attributes(mail_server: "smtp.example.com", mail_port: 587, mail_sender_address: "a@example.test",
        mail_username: username, mail_password: password)
    end
    MailSettings.current(site, env: {}, production: false, address: nil, stand_in: nil)
  end

  def reply(line) = Net::SMTP::Response.parse(line)

  def failure(error, command: nil)
    MailFailure.mark(error, command) if command
    MailFailure.from(error, settings)
  end

  def sentence(error, **)
    failure(error, **).sentence(server: "smtp.example.com", port: 587)
  end

  test "each error maps to its key and sentence" do
    login = Net::SMTPAuthenticationError.new(reply("535 5.7.8 Authentication failed"))
    assert_equal "login", failure(login).key
    assert_equal "The server refused the login. Check username and password.", sentence(login)

    connect = [ Errno::ECONNREFUSED.new("connect(2) for 127.0.0.1:587"), Errno::EHOSTUNREACH.new, Net::OpenTimeout.new("execution expired"),
                Net::ReadTimeout.new, SocketError.new("getaddrinfo: nodename nor servname provided") ]
    connect.each do |error|
      assert_equal "connect", failure(error).key, error.class.name
      assert_equal "Could not reach smtp.example.com on port 587. Check server and port.", sentence(error)
    end
    assert_empty connect.map(&:class) - MailFailure::CONNECTION_ERRORS, "each is a connection error, which the job retries"

    security = [
      OpenSSL::SSL::SSLError.new("SSL_connect returned=1 errno=0 state=error: wrong version number"),
      Net::SMTPUnsupportedCommand.new(nil, message: "STARTTLS is not supported on this server"),
      MailFailure.mark(Net::SMTPServerBusy.new(reply("454 4.7.0 TLS not available")), :starttls)
    ]
    security.each do |error|
      assert_equal "security", failure(error).key, error.message
      assert_equal "The server expects a different security setting. Try STARTTLS with port 587, or TLS with port 465.", sentence(error)
    end

    [ "550 5.7.1 Sender address rejected", "553 5.7.1 Sender not owned by user" ].each do |line|
      error = Net::SMTPFatalError.new(reply(line))
      assert_equal "sender", failure(error, command: :mailfrom).key, line
      assert_equal "The server refused the sender address.", sentence(error)
    end

    others = [
      MailFailure.mark(Net::SMTPFatalError.new(reply("550 5.1.1 No such user")), :rcptto),
      Net::SMTPFatalError.new(reply("550 5.7.1 Rejected")),
      MailFailure.mark(Net::SMTPFatalError.new(reply("554 5.7.1 Message refused")), :mailfrom),
      ArgumentError.new("SMTP From address may not be blank"),
      MailFailure.mark(OpenSSL::SSL::SSLError.new("SSL_read: unexpected eof while reading"), :mailfrom),
      RuntimeError.new("anything")
    ]
    others.each do |error|
      assert_equal "other", failure(error).key, error.message
      assert_equal "The mail could not be sent.", sentence(error)
    end

    assert_equal %w[login connect security sender other], MailFailure::KEYS
  end

  test "the line is the server's one reply line, or what the connection said, and a bug says its class only" do
    assert_equal "535 5.7.8 Authentication failed", failure(Net::SMTPAuthenticationError.new(reply("535 5.7.8 Authentication failed\n"))).line
    assert_equal "Connection refused - connect(2) for 127.0.0.1:587", failure(Errno::ECONNREFUSED.new("connect(2) for 127.0.0.1:587")).line
    assert_equal "NoMethodError", failure(NoMethodError.new("undefined method 'x' for #<User email_address: \"b@example.test\">")).line
    assert_operator failure(Net::SMTPFatalError.new(reply("550 #{"x" * 1000}"))).line.length, :<=, MailFailure::LINE_LIMIT
  end

  test "the username and the password are replaced by … in the server's line wherever they appear" do
    plain = Base64.strict_encode64("\0#{USERNAME}\0#{PASSWORD}")
    lines = [
      "535 5.7.8 Authentication failed for #{USERNAME}",
      "535 5.7.8 Authentication failed for #{USERNAME.upcase} with #{PASSWORD}",
      "535 5.7.8 #{PASSWORD}#{PASSWORD} bad",
      "535 5.7.8 credentials #{plain} rejected",
      "535 5.7.8 user #{Base64.strict_encode64(USERNAME)} pass #{Base64.strict_encode64(PASSWORD)}"
    ]
    lines.each do |line|
      scrubbed = failure(Net::SMTPAuthenticationError.new(reply(line))).line
      assert_includes scrubbed, "…", line
      [ USERNAME, PASSWORD, plain, Base64.strict_encode64(USERNAME), Base64.strict_encode64(PASSWORD) ].each do |secret|
        assert_not_includes scrubbed.downcase, secret.downcase, line
      end
    end

    assert_equal "535 5.7.8 Authentication failed", MailFailure.from(Net::SMTPAuthenticationError.new(reply("535 5.7.8 Authentication failed")),
      settings(username: nil, password: nil)).line, "no login, nothing to replace"
  end

  test "a stored failure reads back as the same failure, and nothing stored is nil" do
    stored = failure(Net::SMTPAuthenticationError.new(reply("535 5.7.8 Authentication failed for #{USERNAME}"))).to_h
    assert_equal({ "key" => "login", "line" => "535 5.7.8 Authentication failed for …" }, stored)
    assert_equal [ "login", "535 5.7.8 Authentication failed for …" ], MailFailure.load(stored).then { [ it.key, it.line ] }
    assert_nil MailFailure.load(nil)
    assert_equal "other", MailFailure.load({ "key" => "gone", "line" => "x" }).key, "a key no longer known reads as other"
  end
end
