require "net/smtp"
require "openssl"
require "base64"

# What a failed send is called (spec, "A failure's sentence"; docs/reference/
# mail.md): a KEY by what the SMTP exchange raised, the SENTENCE for that key
# (`config/locales/mail.en.yml`, `mail.failure.*`), and the server's one reply
# LINE with the effective login replaced by "…". `MailSettings.record_failure!`
# stores the key and the line (`to_h`); System status shows the sentence, the
# Mail card the sentence and the line.
#
#   login     Net::SMTPAuthenticationError (a 535)
#   connect   CONNECTION_ERRORS: refused, unreachable, a timeout, an unknown
#             host. The same list is what MailDeliveryJob retries.
#   security  an SSL error (a TLS handshake that failed: TLS on a plain
#             port, STARTTLS on a TLS port, a certificate that isn't the
#             server's), STARTTLS not offered ("STARTTLS is not supported on
#             this server", which net-smtp raises before sending anything),
#             or any reply to the STARTTLS command itself
#   sender    a 550 or 553 to MAIL FROM
#   other     anything else, a 550 to RCPT TO (the RECIPIENT refused) included
#
# WHICH COMMAND FAILED is not in a Net::SMTP error: a 550 is a 550 whether the
# server said it to MAIL FROM or to RCPT TO, and a 454 to STARTTLS is the same
# class as a 454 to AUTH. `ApplicationMailer::SmtpDelivery` notes the command
# in progress on the error (`mark`), and `from` reads it (`command_of`).
#
# THE LINE. A Net::SMTP error carries the server's reply: its first line. A
# connection or TLS error carries the system's sentence ("Connection refused
# - connect(2) for 127.0.0.1:587"), which names nothing but the server. Any
# other error is a bug or the mail gem's own refusal, whose message can quote
# anything (a record's inspect, an address): its line is the class name only.
#
# THE SCRUB. Some servers echo the login in a refusal ("535 Authentication
# failed for ana@example.org"), and for several providers the username IS a
# credential (Postmark's server token, SES's access key id), so the effective
# username and password are replaced by "…" wherever they appear, in any
# case, and so are their Base64 forms and AUTH PLAIN's blob (a server that
# echoes what it was sent echoes those). The longest first, so a password
# that contains the username is not half replaced.
class MailFailure
  KEYS = %w[login connect security sender other].freeze

  CONNECTION_ERRORS = [
    Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, Errno::ETIMEDOUT,
    Net::OpenTimeout, Net::ReadTimeout, SocketError
  ].freeze

  SENDER_STATUSES = %w[550 553].freeze
  LINE_LIMIT = 300
  HIDDEN = "…".freeze

  attr_reader :key, :line

  # `settings` is a MailSettings, read for the effective login alone.
  def self.from(error, settings)
    new(key: key_for(error), line: scrub(line_for(error), settings.value(:username), settings.value(:password)))
  end

  # The same error with the login replaced by "…" in its reply, for an error
  # that is about to be raised past Action Mailer, whose log subscriber
  # writes a failed delivery's message at info ("Failed delivery of mail ...
  # error_message=..."). A reply is the one place the login can be in: any
  # other error is answered as it is. The copy keeps the class (the job's
  # retry and the key read it) and the backtrace.
  def self.scrubbed(error, username:, password:)
    return error unless error.is_a?(Net::SMTPError) && error.response

    reply = Net::SMTP::Response.parse(scrub(error.response.string, username, password))
    error.class.new(reply).tap { |copy| copy.set_backtrace(error.backtrace) if error.backtrace }
  end

  # What `MailSettings#failure` holds ({ "key", "line" }), or nil. A key this
  # code no longer knows reads as `other`.
  def self.load(stored)
    return if stored.blank?

    new(key: stored["key"], line: stored["line"])
  end

  # Notes on `error` the SMTP command that was in progress; answers the error.
  def self.mark(error, command)
    error.instance_variable_set(:@mail_command, command&.to_sym)
    error
  end

  def self.command_of(error) = error.instance_variable_get(:@mail_command)

  def self.key_for(error)
    case error
    when *CONNECTION_ERRORS then "connect"
    when Net::SMTPAuthenticationError then "login"
    when OpenSSL::SSL::SSLError then "security"
    when Net::SMTPUnsupportedCommand
      error.message.to_s.include?("STARTTLS") ? "security" : "other"
    when Net::SMTPError
      case command_of(error)
      when :starttls then "security"
      when :mailfrom then SENDER_STATUSES.include?(status_of(error)) ? "sender" : "other"
      else "other"
      end
    else "other"
    end
  end

  def self.line_for(error)
    text =
      case error
      when Net::SMTPError then error.response&.string || error.message
      when *CONNECTION_ERRORS, OpenSSL::SSL::SSLError then error.message
      else error.class.name
      end
    text.to_s.lines.first.to_s.strip.truncate(LINE_LIMIT, omission: HIDDEN)
  end

  def self.status_of(error) = error.response&.status.to_s

  def self.scrub(line, username, password)
    username = username.presence
    password = password.presence
    secrets = [ username, password ].compact
    secrets += secrets.map { |secret| Base64.strict_encode64(secret) }
    secrets << Base64.strict_encode64("\0#{username}\0#{password}") if username && password
    secrets.uniq.sort_by { -it.length }.reduce(line) do |scrubbed, secret|
      scrubbed.gsub(Regexp.new(Regexp.escape(secret), Regexp::IGNORECASE), HIDDEN)
    end
  end

  private_class_method :key_for, :line_for, :status_of, :scrub

  def initialize(key:, line:)
    @key = KEYS.include?(key.to_s) ? key.to_s : "other"
    @line = line.to_s
  end

  # The sentence a person reads. `server` and `port` are the effective ones,
  # named by the connect sentence only.
  def sentence(server:, port:)
    I18n.t("mail.failure.#{key}", server: server, port: port, raise: true)
  end

  def to_h = { "key" => key, "line" => line }
end
