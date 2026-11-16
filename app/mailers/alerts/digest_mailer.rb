module Alerts
  # The owners' digest of alerts (`Alerts::Mailing` queues it): a line per
  # alert, newest first, up to LISTED and then how many more, and one button
  # to System status. Handed the owner and the alerts' ids; the alerts are
  # read here, in the job, so one deleted since (pruned, or its row gone) is
  # skipped, and with none left no mail is built.
  #
  # An alert's line is drawn from `Alert#sentence`, the data the model
  # hands up, with this mail's own keys (`mail.alerts_mailer.digest.*`): an
  # error is its class and its place in the code, never its message, and a
  # security alert names what the audit log's rule saw, never an address or
  # a typed email. Its link follows `ApplicationMailer#link_origin`, the
  # rule every mailed link follows; the digest asks the same rule before it
  # queues, so a mail that finds no origin here is one whose address went
  # away in between, and one line says so, naming nobody.
  class DigestMailer < ApplicationMailer
    LISTED = 20
    NOT_SENT = Mailing::NO_ADDRESS

    helper_method :system_status_url, :alert_kind, :alert_sentence, :alert_facts, :digest_every

    def digest(owner, alert_ids)
      alerts = Alert.where(id: alert_ids).order(last_seen_at: :desc, id: :desc).to_a
      return if alerts.empty?

      @url_options = link_origin(nil)
      if @url_options.empty?
        Rails.logger.warn NOT_SENT
        return
      end

      @count = alerts.size
      @alerts = alerts.first(LISTED)
      @more = @count - @alerts.size
      mail subject: t("mail.alerts_mailer.digest.subject", count: @count, site: site_name), to: owner.email_address
    end

    private

    # `port: nil` first, for the reason `PasswordsMailer#reset_url` gives.
    def system_status_url = admin_system_status_url(port: nil, **@url_options)

    def alert_kind(alert) = t("mail.alerts_mailer.digest.kinds.#{alert.security? ? "security" : "error"}")

    def alert_sentence(alert)
      sentence = alert.sentence
      t("mail.alerts_mailer.digest.sentences.#{sentence.key}", **sentence.values)
    end

    def digest_every = Alert::DIGEST_EVERY.in_minutes.to_i

    # "12 times · last 16 Nov 2026, 13:47", in the site's zone.
    def alert_facts(alert)
      time = I18n.l(alert.last_seen_at.in_time_zone(SiteSetting.instance.effective_time_zone), format: :"admin.datetime")
      t("mail.alerts_mailer.digest.facts", count: alert.occurrences, time: time)
    end
  end
end
