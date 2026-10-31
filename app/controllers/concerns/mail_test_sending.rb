# Sending a test mail and wording its outcome, for the two screens that offer
# one: Settings → Mail (`Admin::SettingsController#send_test_mail`) and the
# setup wizard's Mail step. One mail to the person pressing it, sent now and in
# this request with the SAVED settings (`ApplicationMailer.deliver_now_and_record`,
# bounded by `MailSettings`' timeouts), its outcome recorded as any send's is.
#
# Answers a Hash the caller hands to `Admin::SettingsScreen::MailTestOutcomeComponent`
# (and, for the status, reads `:status`):
#   { sent: true, status: :ok }
#   { alert: <sentence>, line: <the server's line>, status: :unprocessable_entity }
#   { alert: <the state's own sentence>, status: :unprocessable_entity }  -- the
#     settings are not complete, nothing was sent.
# The sentences are the spec's (`MailFailure#sentence`, `admin.mail.states`), so
# there is one place to change them.
module MailTestSending
  extend ActiveSupport::Concern

  private

  def deliver_test_mail
    settings = MailSettings.current
    unless settings.complete?
      return { alert: MailStateSentence.for(settings), status: :unprocessable_entity }
    end

    failure = ApplicationMailer.deliver_now_and_record(SystemMailer.test_mail(Current.user))
    return { sent: true, status: :ok } unless failure

    { alert: failure.sentence(server: settings.value(:server), port: settings.value(:port)), line: failure.line, status: :unprocessable_entity }
  end
end
