# The mails the system sends about itself. Today one: the test mail, which
# Settings and the setup wizard send at once (`deliver_now_and_record`)
# because its answer is the point. It needs no link, so no site address.
class SystemMailer < ApplicationMailer
  def test_mail(user)
    mail subject: t("mail.test.subject", site: site_name), to: user.email_address
  end
end
