require "test_helper"

# A submission's mail to a form's recipients (forms plan, Task 3): every
# label with its answer in the form's order, then when, in which language
# and from which page; Reply-To the visitor's email answer; built in the job
# from the delivery, whose Global ID is all the job carries.
class FormsMailerTest < ActionMailer::TestCase
  def submission(form, answers, page: nil, locale: "en")
    clean = Forms::Answers.clean(form.fields, answers, locale: locale)
    assert_empty clean.errors
    record = Forms::Submission.create!(form: form, page: page, locale: locale, answers: clean.values)
    record.deliveries.create!(kind: "mail", destination: form.destinations.first || form.destinations.create!(kind: "mail", settings: { "recipients" => "office@example.com" }))
  end

  test "the mail lists every label with its answer, in order, and replies to the visitor's email answer" do
    with_mail_state(:working) do
      page = root_page
      delivery = submission(forms(:contact), { "f_name0001" => "Ada Lovelace", "f_mail0001" => "ada@example.com", "f_text0001" => "Line one\nLine two" }, page: page)
      mail = FormsMailer.submission(delivery)

      assert_equal [ "office@example.com" ], mail.to
      assert_equal [ "ada@example.com" ], mail.reply_to
      assert_equal [ "no-reply@example.test" ], mail.from
      assert_equal "New submission: Contact", mail.subject

      text = mail.text_part.body.decoded
      positions = [ "Your name", "Ada Lovelace", "Email address", "ada@example.com", "Message", "Line one" ].map { |part| text.index(part) }
      assert_equal positions.sort, positions, "labels and answers in the form's order"
      assert_includes text, "Line two"
      assert_includes text, "English"
      assert_includes text, "Home"
      assert_includes mail.html_part.body.decoded, "Ada Lovelace"
    end
  end

  test "without an email answer there is no Reply-To" do
    with_mail_state(:working) do
      form = forms(:newsletter)
      form.destinations.create!(kind: "mail", settings: { "recipients" => "office@example.com" })
      delivery = submission(form, { "f_mail0002" => "bea@example.com", "f_okay0002" => "1" })
      assert_equal [ "bea@example.com" ], FormsMailer.submission(delivery).reply_to

      record = Forms::Submission.create!(form: forms(:contact), locale: "en",
        answers: [ { "key" => "f_name0001", "type" => "short_text", "label" => "Your name", "value" => "Ada", "display" => "Ada" } ])
      delivery = record.deliveries.create!(kind: "mail", destination: form_destinations(:contact_mail))
      mail = FormsMailer.submission(delivery)
      assert_empty Array(mail.reply_to)
      assert_includes mail.text_part.body.decoded, "Ada"
    end
  end

  test "an answer that looks like markup is text in the HTML part" do
    with_mail_state(:working) do
      delivery = submission(forms(:contact), { "f_name0001" => "<script>alert(1)</script>", "f_mail0001" => "ada@example.com", "f_text0001" => "<b>bold</b>" })
      html = FormsMailer.submission(delivery).html_part.body.decoded

      assert_not_includes html, "<script>"
      assert_not_includes html, "<b>bold</b>"
      assert_includes html, "&lt;script&gt;alert(1)&lt;/script&gt;"
    end
  end

  test "an answer left blank reads as no answer" do
    with_mail_state(:working) do
      delivery = submission(forms(:contact), { "f_name0001" => "Ada", "f_mail0001" => "ada@example.com" })
      assert_includes FormsMailer.submission(delivery).text_part.body.decoded, "(no answer)"
    end
  end
end
