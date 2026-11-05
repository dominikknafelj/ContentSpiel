# A submission's mail to a form's recipients (the mail destination,
# `Forms::Destinations::Mail`): built and sent in
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
#
# NEVER LOGGED WHOLE. Action Mailer's log subscriber writes every delivered
# mail in full at debug (`ActionMailer::LogSubscriber#deliver`, from the
# `deliver.action_mailer` payload's `:mail`), which for this mailer is the
# answers and the visitor's address. The payload is filled by the mailer
# class's `set_payload_for_mail`, so this mailer puts a placeholder in the
# place of the encoded mail: the debug line says the mail is not logged,
# whatever `RAILS_LOG_LEVEL` says, and the info line ("Delivered mail
# <id>") stays (test/mailers/forms_mailer_test.rb: "a form's mail is in no
# log line, at debug either"). The other mailers are logged as Rails logs
# them (docs/reference/hosting.md).
class FormsMailer < ApplicationMailer
  NOT_LOGGED = "(a form's mail is not logged: it holds a visitor's answers)".freeze

  helper_method :answers, :sent_at, :language_name, :page_title

  # Rails' private class hook that fills the delivery's payload; the
  # payload's `:mail` is the one member that holds the body.
  def self.set_payload_for_mail(payload, mail)
    super
    payload[:mail] = NOT_LOGGED
  end
  private_class_method :set_payload_for_mail

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
