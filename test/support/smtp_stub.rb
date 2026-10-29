require "socket"
require "openssl"
require "net/smtp"
require "base64"

# A local SMTP server for the tests of the SMTP exchange itself: a stdlib
# `TCPServer` on 127.0.0.1 and an ephemeral port, never the network. It
# answers one script and records every command line it received (`commands`)
# and every message it accepted (`messages`).
#
#   SmtpStub.start(:success) do |port, stub|
#     ... send to 127.0.0.1:port ...
#     stub.commands # => ["EHLO ...", "STARTTLS", "EHLO ...", "AUTH PLAIN ...", "MAIL FROM:<...>", ...]
#   end
#
# Scripts (`SCRIPTS`):
#   :success           a whole exchange, STARTTLS and AUTH PLAIN offered
#   :login_refused     535 on AUTH, echoing the username the client sent
#                      (some servers do; the stored line must not hold it)
#   :sender_refused    550 on MAIL FROM
#   :starttls_refused  offers STARTTLS and answers it with 454
#   :no_starttls       does not offer STARTTLS at all
#   :silent            accepts the connection and never says a word
#
# STARTTLS is real: the server side upgrades the socket with a self-signed
# certificate for 127.0.0.1 made once per process (`certificate`). The client
# trusts it only inside `SmtpStub.trusted { }`, which hands Net::SMTP a
# context that knows that certificate, so nothing about verification is
# turned off in the code under test.
#
# `SmtpStub.closed_port` is a port on 127.0.0.1 that nobody listens on (bound
# and closed again): a connection to it is refused at once.
class SmtpStub
  SCRIPTS = %i[success login_refused sender_refused starttls_refused no_starttls silent].freeze
  HOST = "127.0.0.1".freeze

  attr_reader :port, :commands, :messages

  def self.start(script = :success)
    stub = new(script)
    stub.listen
    yield stub.port, stub
    stub
  ensure
    stub&.stop
  end

  def self.closed_port
    server = TCPServer.new(HOST, 0)
    server.addr[1]
  ensure
    server&.close
  end

  # Net::SMTP builds its client context from `default_ssl_context`
  # (Mail::SMTP#ssl_context): for the block it is one that trusts the stub's
  # certificate, with peer and host verification as they always are.
  def self.trusted
    original = Net::SMTP.method(:default_ssl_context)
    Net::SMTP.define_singleton_method(:default_ssl_context) do |*args|
      original.call(*args).tap do |context|
        store = OpenSSL::X509::Store.new
        store.add_cert(SmtpStub.certificate.first)
        context.cert_store = store
      end
    end
    yield
  ensure
    Net::SMTP.define_singleton_method(:default_ssl_context, original)
  end

  def self.certificate
    @certificate ||= begin
      key = OpenSSL::PKey::EC.generate("prime256v1")
      cert = OpenSSL::X509::Certificate.new
      cert.version = 2
      cert.serial = 1
      cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=#{HOST}")
      cert.public_key = key
      cert.not_before = Time.now - 60
      cert.not_after = Time.now + 3600
      extensions = OpenSSL::X509::ExtensionFactory.new
      extensions.subject_certificate = extensions.issuer_certificate = cert
      cert.add_extension(extensions.create_extension("subjectAltName", "IP:#{HOST}", false))
      cert.add_extension(extensions.create_extension("basicConstraints", "CA:TRUE", true))
      cert.sign(key, OpenSSL::Digest.new("SHA256"))
      [ cert, key ]
    end
  end

  def initialize(script)
    raise ArgumentError, "unknown SMTP script #{script.inspect}" unless SCRIPTS.include?(script)

    @script = script
    @commands = []
    @messages = []
    @clients = []
  end

  def listen
    @server = TCPServer.new(HOST, 0)
    @port = @server.addr[1]
    @thread = Thread.new do
      Thread.current.report_on_exception = false
      loop do
        client = @server.accept
        @clients << client
        serve(client)
      rescue IOError, SystemCallError, OpenSSL::SSL::SSLError
        # The client went away, or the stub is stopping: next connection.
        break if @server.closed?
      ensure
        client&.close unless @script == :silent
      end
    end
  end

  def stop
    @server&.close
    @thread&.kill&.join(1)
    @clients.each { |client| client.close unless client.closed? }
  end

  # The command lines received, verb first, e.g. "MAIL FROM:<a@example.test>".
  def verbs = commands.map { |line| line.split(/[\s:]/, 2).first.upcase }

  private

  def serve(socket)
    return sleep if @script == :silent

    io = socket
    say io, "220 stub.test ESMTP ready"
    while (line = io.gets)
      line = line.chomp
      commands << line
      verb = line.split(/[\s:]/, 2).first.to_s.upcase
      case verb
      when "EHLO", "HELO" then ehlo(io, tls: io != socket)
      when "STARTTLS"
        if @script == :starttls_refused
          say io, "454 4.7.0 TLS not available"
        else
          say io, "220 2.0.0 Ready to start TLS"
          io = upgrade(socket)
        end
      when "AUTH"
        if @script == :login_refused
          say io, "535 5.7.8 Authentication failed for #{login_of(line)}"
        else
          say io, "235 2.7.0 Authentication successful"
        end
      when "MAIL"
        say io, (@script == :sender_refused ? "550 5.7.1 Sender address rejected" : "250 2.1.0 Ok")
      when "RCPT" then say io, "250 2.1.5 Ok"
      when "DATA"
        say io, "354 End data with <CR><LF>.<CR><LF>"
        messages << read_data(io)
        say io, "250 2.0.0 Ok: queued"
      when "QUIT"
        say io, "221 2.0.0 Bye"
        break
      when "RSET", "NOOP" then say io, "250 2.0.0 Ok"
      else say io, "502 5.5.2 Command not recognized"
      end
    end
  end

  def ehlo(io, tls:)
    lines = [ "stub.test", "AUTH PLAIN LOGIN" ]
    lines << "STARTTLS" unless tls || @script == :no_starttls
    lines << "8BITMIME"
    lines[0...-1].each { |text| say io, "250-#{text}" }
    say io, "250 #{lines.last}"
  end

  def upgrade(socket)
    cert, key = self.class.certificate
    context = OpenSSL::SSL::SSLContext.new
    context.cert = cert
    context.key = key
    ssl = OpenSSL::SSL::SSLSocket.new(socket, context)
    ssl.sync_close = true
    ssl.accept
  end

  def read_data(io)
    body = +""
    while (line = io.gets)
      break if line.chomp == "."
      body << line
    end
    body
  end

  # AUTH PLAIN's initial response is base64 of "\0user\0password".
  def login_of(line)
    Base64.decode64(line.split(" ", 3)[2].to_s).split("\0")[1].to_s
  end

  def say(io, text)
    io.write("#{text}\r\n")
    io.flush
  end
end
