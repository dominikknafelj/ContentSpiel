require "mail"

class ApplicationMailer
  # The mail gem's SMTP delivery, telling which command a refusal answered.
  #
  # A Net::SMTP error does not say what it was a reply to: a 550 to MAIL FROM
  # (the SENDER refused, which the owner can fix in Settings) and a 550 to RCPT
  # TO (one recipient's address) are the same class with the same code, and
  # so are a 454 to STARTTLS (security) and a 454 to AUTH. The session is
  # extended so each command a refusal can answer notes its name before it
  # is sent, and the error that leaves `deliver!` carries the last one
  # (`MailFailure.mark`), which `MailFailure.from` reads.
  #
  # And the error leaves with the login scrubbed from the server's reply
  # (`MailFailure.scrubbed`): a server that echoes the login in a 535 would
  # otherwise put it in Action Mailer's "Failed delivery" log line, which is
  # written at info. It is raised with no `cause`, so the original reply is
  # not reachable from it either.
  #
  # Nothing else differs from `Mail::SMTP`: the same settings, the same
  # Net::SMTP, the same verification of the server's certificate.
  class SmtpDelivery < Mail::SMTP
    module Commands
      attr_reader :mail_command

      %i[starttls authenticate mailfrom rcptto data].each do |name|
        define_method(name) do |*args, **options, &block|
          @mail_command = name
          super(*args, **options, &block)
        end
      end
    end

    def deliver!(mail)
      super
    rescue StandardError => error
      error = MailFailure.scrubbed(error, username: settings[:user_name], password: settings[:password])
      raise MailFailure.mark(error, @session&.mail_command), cause: nil
    end

    private

    def build_smtp_session
      @session = super.extend(Commands)
    end
  end
end
