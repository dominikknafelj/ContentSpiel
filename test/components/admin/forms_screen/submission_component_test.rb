require "test_helper"

# One submission (forms plan, Task 5; design.md 3): every answer as text
# under its label as sent, then each destination's result, with Send again
# for a failed one to a holder of `form_submissions.view`.
class Admin::FormsScreen::SubmissionComponentTest < ViewComponent::TestCase
  def t(key, **values) = I18n.t("admin.components.forms_screen.submission.#{key}", **values)

  def row(key, type, label, value, display: value) = { "key" => key, "type" => type, "label" => label, "value" => value, "display" => display }

  def submission(*rows) = Forms::Submission.create!(form: forms(:contact), locale: "en", answers: rows)

  def draw(record) = render_inline(Admin::FormsScreen::SubmissionComponent.new(submission: record))

  def grant(user, *keys)
    group = AccessControl::Group.create!(name: "Extra #{user.id} #{keys.join(" ")}")
    keys.each { |key| group.grants.create!(permission: key, scope: {}) }
    AccessControl::Membership.create!(user: user, group: group)
    user
  end

  test "an answer that looks like markup is text" do
    Current.actor = users(:one)
    record = submission(row("f_name0001", "short_text", "Your <i>name</i>", "<b>Ada</b>"),
      row("f_mail0001", "email", "Email address", "ada@example.com"),
      row("f_text0001", "long_text", "Message", "<script>alert(1)</script>\nsecond line"),
      row("f_extra001", "short_text", "Left empty", nil, display: ""))
    draw(record)

    assert_selector "dl dt", text: "Your <i>name</i>"
    assert_no_selector "dl i"
    assert_selector "dl dd", text: "<b>Ada</b>"
    assert_no_selector "dl b"
    assert_no_selector "dl script"
    assert_selector "dl dd a[href='mailto:ada@example.com']", text: "ada@example.com"
    assert_selector "dl dd", text: t("not_answered")
  end

  test "Send again is shown only for a failed delivery, to a holder of form_submissions.view" do
    record = submission(row("f_name0001", "short_text", "Your name", "Ada"))
    sent, waiting, failed = Array.new(3) { record.deliveries.create!(kind: "mail", destination: form_destinations(:contact_mail)) }
    sent.record_sent!(at: Time.current)
    failed.record_failed!(key: "login", line: "535 refused for ada", at: Time.current)

    Current.actor = grant(users(:author), "form_submissions.view")
    draw(record)
    assert_selector "[data-delivery-state]", count: 3
    assert_selector "[data-delivery-state='failed']", text: t("reasons.mail", reason: I18n.t("admin.mail.reasons.login"))
    assert_no_text "535 refused", wait: 0
    assert_selector "form[action$='/form_deliveries/#{failed.id}/resend'] button", text: t("send_again"), count: 1
    assert_selector "button", text: t("send_again"), count: 1
    assert_no_selector "button", text: t("delete_button"), wait: 0

    Current.actor = users(:reader)
    draw(record)
    assert_no_selector "button", text: t("send_again"), wait: 0
  end

  test "each failure key has its sentence, and a key this code doesn't know reads as the plain one" do
    Current.actor = users(:one)
    record = submission(row("f_name0001", "short_text", "Your name", "Ada"))
    %w[not_ready gave_up no_destination unknown_destination error other acme_said_no].each do |key|
      record.deliveries.create!(kind: "mail", destination: form_destinations(:contact_mail)).record_failed!(key: key, line: "421 the other side said so", at: Time.current)
    end
    draw(record)

    expected = [
      t("reasons.not_ready"), t("reasons.gave_up", count: Forms::DeliveryJob::ATTEMPTS), t("reasons.no_destination"),
      t("reasons.unknown_destination"), t("reasons.error"), t("reasons.mail", reason: I18n.t("admin.mail.reasons.other")), t("reasons.unknown")
    ]
    assert_equal expected.size, expected.uniq.size
    assert_equal expected, page.all("[data-delivery-state='failed'] [data-failure]").map { |node| node.text.strip }
    assert_no_text "the other side said so", wait: 0
  end

  test "a submission that can't be read says so in place of its answers" do
    Current.actor = users(:one)
    record = submission(row("f_name0001", "short_text", "Your name", "Ada"))
    other = ActiveRecord::Encryption::DerivedSecretKeyProvider.new("keys that are not the site's")
    ActiveRecord::Encryption.with_encryption_context(key_provider: other) do
      draw(Forms::Submission.find(record.id))
    end
    assert_text t("unreadable")
    assert_no_selector "dl"
    assert_selector "button", text: t("delete_button")
  end
end
