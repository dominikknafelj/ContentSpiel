require "test_helper"

# One submission: every answer as text
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

  # Where the destination is gone Send again would only fail
  # again, so it is not offered; a delivery that gave up still gets it.
  test "Send again is hidden for a removed destination and an unknown type, and shown for one that gave up" do
    Current.actor = users(:one)
    record = submission(row("f_name0001", "short_text", "Your name", "Ada"))
    deliveries = %w[no_destination unknown_destination gave_up].map do |key|
      record.deliveries.create!(kind: "mail", destination: form_destinations(:contact_mail)).tap { it.record_failed!(key: key, line: nil, at: Time.current) }
    end
    draw(record)

    removed, unknown, gave_up = deliveries
    assert_no_selector "form[action$='/form_deliveries/#{removed.id}/resend']", wait: 0
    assert_no_selector "form[action$='/form_deliveries/#{unknown.id}/resend']", wait: 0
    assert_selector "form[action$='/form_deliveries/#{gave_up.id}/resend'] button", text: t("send_again")
    assert_selector "button", text: t("send_again"), count: 1
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

  # A sent delivery's time is the clock alone on the day the submission came
  # in (the meta line above says that day), and the day with it after.
  test "each delivery's state is a state chip in its word: Sent with its time, Waiting, Sending, Not delivered in warn, never red" do
    Current.actor = users(:one)
    received = Time.zone.local(2026, 11, 9, 13, 58)
    record, sent, later, waiting, sending, failed = travel_to(received) do
      made = submission(row("f_name0001", "short_text", "Your name", "Ada"))
      [ made, *Array.new(5) { made.deliveries.create!(kind: "mail", destination: form_destinations(:contact_mail)) } ]
    end
    sent.record_sent!(at: Time.zone.local(2026, 11, 9, 14, 5))
    later.record_sent!(at: Time.zone.local(2026, 11, 10, 9, 30))
    sending.record_attempt!
    failed.record_failed!(key: "login", line: nil, at: received)
    draw(record)

    chip = ->(delivery) { page.find("li[data-delivery-id='#{delivery.id}'] .admin-state-chip") }
    assert_equal [ "ok", t("states.sent") ], [ chip.(sent)["data-state-tone"], chip.(sent).text.strip ]
    assert_selector "li[data-delivery-id='#{sent.id}'][data-delivery-state=sent]", text: "#{t("states.sent")} · 14:05"
    assert_selector "li[data-delivery-id='#{later.id}']", text: "#{t("states.sent")} · 10 Nov, 09:30"
    assert_equal [ "off", t("states.waiting") ], [ chip.(waiting)["data-state-tone"], chip.(waiting).text.strip ]
    assert_equal [ "off", t("states.sending") ], [ chip.(sending)["data-state-tone"], chip.(sending).text.strip ]
    assert_selector "li[data-delivery-id='#{sending.id}'][data-delivery-state=waiting]"
    assert_equal [ "warn", t("states.not_delivered") ], [ chip.(failed)["data-state-tone"], chip.(failed).text.strip ]

    assert_selector "li[data-delivery-id='#{failed.id}'] p.text-small.text-warn-ink[data-failure]"
    assert_equal Admin::Ui::ButtonComponent.classes(:secondary, size: :small).split.sort,
      (page.find("li[data-delivery-id='#{failed.id}'] form button")[:class].split & Admin::Ui::ButtonComponent.classes(:secondary, size: :small).split).sort
    deliveries = page.find("section[aria-labelledby=submission-delivery]")
    assert_no_match(/(?<![\w-])(?:bg|text|border)-danger/, deliveries.native.to_html, "no delivery state is red")
    own_dots = deliveries.native.css("[class~='bg-ok'], [class~='bg-warn']").reject { |dot| dot.ancestors(".admin-state-chip").any? }
    assert_empty own_dots, "a state's dot is the state chip's, not one of its own"
  end

  test "the answers and deliveries are the shared card frame, and the delete zone is a rule, not a box" do
    Current.actor = users(:one)
    record = submission(row("f_name0001", "short_text", "Your name", "Ada"))
    record.deliveries.create!(kind: "mail", destination: form_destinations(:contact_mail))
    draw(record)

    { "submission-answers" => t("answers"), "submission-delivery" => t("delivery") }.each do |id, heading|
      assert_selector "section.admin-settings-card[aria-labelledby=#{id}] > .admin-settings-card__head h2##{id}", text: heading
      assert_selector "section[aria-labelledby=#{id}] > .admin-settings-card__head span[aria-hidden=true].bg-ic-form-bg svg"
    end
    assert_selector ".admin-settings-card", count: 2
    assert_selector "section[aria-labelledby=submission-answers] dl dd.text-body", text: "Ada"

    zone = page.find("section.admin-action-zone.mt-2[data-zone=delete][aria-labelledby=submission-delete-title]")
    classes = zone[:class].split
    assert_includes classes, "border-t"
    assert_includes classes, "border-line"
    assert_empty classes & %w[border rounded-cs rounded-card], "the delete zone is a rule above its words, not a box"
    assert zone.has_selector?("button", text: t("delete_button"))
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
