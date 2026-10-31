# The one sentence a `MailSettings#state` is told in (spec "The states", design
# answer M3; `config/locales/admin/mail.en.yml`): "Working. Last mail sent
# 14 Oct, 09:12." or "Last send failed 14 Oct, 09:12: could not reach the
# server." Shared by the Settings card's header
# (`Admin::SettingsScreen::MailStateComponent`) and System status's Mail row
# (`Setup::SystemCheck`), so the two cannot say different things.
#
# A failure is said by its SHORT reason (`admin.mail.reasons.*`) and never by
# the server's line, which `settings.manage` alone reads on the card: the
# row is open to `system_status.view`. Times are in the zone the request
# runs in (the site's, `Admin::BaseController`).
module MailStateSentence
  def self.for(settings)
    case settings.state
    when :not_set_up
      I18n.t("admin.mail.states.not_set_up.#{settings.not_set_up_key}")
    when :untested then I18n.t("admin.mail.states.untested.sentence")
    when :working then I18n.t("admin.mail.states.working.sentence", at: moment(settings.last_sent_at))
    when :failed
      key = MailFailure.load(settings.failure)&.key || "other"
      I18n.t("admin.mail.states.failed.sentence", at: moment(settings.failed_at), reason: I18n.t("admin.mail.reasons.#{key}"))
    end
  end

  def self.moment(at) = at ? I18n.l(at.in_time_zone, format: :"admin.short_datetime") : ""
end
