# A submission's mail to a form's recipients (forms plan, Task 3; the mail
# destination, `Forms::Destinations::Mail`): built and sent in
# `Forms::DeliveryJob` from the delivery, whose Global ID is the only thing
# the job carries. The answers are read from the submission here, in the
# job, decrypted: never handed in, so they are in no queue row and no log
# line of Active Job.
#
# For the form's editors, so in the default language (`mail.forms.*`, as
# every mail): the form's name in the subject, every label with its answer
# in the form's order as the submission stored them (the default
# language's labels and displays, as sent), then when it was sent, in which
# language and from which page. Every value is text: an answer that looks
# like markup is escaped in the HTML part as any ERB output is.
#
# Reply-To is the first answer whose value type is the content model's
# email (`Forms::FieldType#value_type`), with a value that is ONE plain
# address (`MailSettings.one_address?`, the sender's own rule, so a header
# can never carry a list or a name the visitor typed). A form with no such
# answer has none, and a reply goes to the sender address.
class FormsMailer < ApplicationMailer
  helper_method :answers, :sent_at, :language_name, :page_title

  def submission(delivery)
    @submission = delivery.submission
    @form = @submission.form
    mail to: delivery.destination.recipients, reply_to: reply_to, subject: t("mail.forms.submission.subject", form: @form.name)
  end

  private

  def answers = @submission.answers

  def reply_to
    row = answers.find { |answer| Forms::FieldTypes.find(answer["type"])&.value_type == :email && answer["value"].present? }
    address = row&.dig("value").to_s
    address if MailSettings.one_address?(address)
  end

  def sent_at = I18n.l(@submission.created_at, format: :long)

  def language_name = Locales.name(@submission.locale)

  # The page's title as its rows have it now, in the default language, or
  # nil: a send from no page, or from one deleted since.
  def page_title = @submission.page && Locales.read(@submission.page, :title, locale: I18n.default_locale)
end
