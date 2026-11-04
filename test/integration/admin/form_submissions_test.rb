require "test_helper"

# A form's submissions in CS Studio (forms plan, Task 5; design.md 3): the
# list, one submission, Send again, delete one and delete all. Reading and
# sending again need `form_submissions.view`, deleting `forms.manage`; a
# submission is found among its form's only, and only ids reach a URL.
class Admin::FormSubmissionsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include LogCapture

  ANSWER = "Ada Lovelace".freeze
  ADDRESS = "ada@example.com".freeze

  def grant(user, *keys)
    group = AccessControl::Group.create!(name: "Extra #{user.id} #{keys.join(" ")}")
    keys.each { |key| group.grants.create!(permission: key, scope: {}) }
    AccessControl::Membership.create!(user: user, group: group)
    user
  end

  def submissions_viewer = grant(users(:author), "form_submissions.view")

  def t(key, **values) = I18n.t("admin.components.forms_screen.#{key}", **values)

  def answers(name = ANSWER, address = ADDRESS)
    [ { "key" => "f_name0001", "type" => "short_text", "label" => "Your name", "value" => name, "display" => name },
      { "key" => "f_mail0001", "type" => "email", "label" => "Email address", "value" => address, "display" => address },
      { "key" => "f_text0001", "type" => "long_text", "label" => "Message", "value" => "Hello", "display" => "Hello" } ]
  end

  def submission(form = forms(:contact), age: 1.minute, page: nil, locale: "en", rows: answers)
    Forms::Submission.create!(form: form, locale: locale, page: page, answers: rows, created_at: age.ago)
  end

  def delivery(record, state = :waiting, key: "login")
    made = record.deliveries.create!(kind: "mail", destination: record.form.destinations.first)
    made.record_sent!(at: Time.current) if state == :sent
    made.record_failed!(key: key, line: "535 refused", at: Time.current) if state == :failed
    made
  end

  test "the list is newest first, 50 a page, and shows time, language, page and summary" do
    form = forms(:newsletter)
    form.destinations.create!(kind: "mail", position: 0, settings: { "recipients" => "office@example.com" })
    rows = ->(name, address) { [ { "key" => "f_mail0002", "type" => "email", "label" => "Email address", "value" => address, "display" => address } ] }
    oldest = submission(form, age: 3.days, rows: rows.call(nil, "oldest@example.com"))
    48.times { |n| submission(form, age: (2.days - n.minutes), rows: rows.call(nil, "person#{n}@example.com")) }
    page = create_page(title: "Contact us")
    trashed = create_page(title: "Old page")
    in_trash = submission(form, age: 2.hours, page: trashed, rows: rows.call(nil, "trash@example.com"))
    Current.set(actor: users(:one)) { assert Trash::Move.call(trashed).ok? }
    newest = submission(form, age: 1.minute, page: page, locale: "de", rows: rows.call(nil, "newest@example.com"))
    delivery(newest, :failed)

    sign_in_as users(:two)
    get admin_form_submissions_path(form)
    assert_response :ok
    assert_select "h1", text: "Newsletter"
    assert_select "nav a[aria-current='page']", text: t("tabs.submissions")
    assert_select "nav a[href='#{admin_form_path(form)}']", text: t("tabs.form")
    assert_select "p", text: t("submissions_list.kept", count: 30)
    assert_select "table tbody tr", count: 50
    first = css_select("table tbody tr").first
    assert_includes first.text, "newest@example.com"
    assert_includes first.text, "DE"
    assert_includes first.text, "Contact us"
    assert_includes first.text, t("submissions_list.not_delivered")
    assert_select first, "a[href='#{admin_form_submission_path(form, newest)}']"
    assert_select "table tbody tr", text: /trash@example\.com/ do |row|
      assert_includes row.text, t("submissions_list.page_trashed")
    end
    assert_select "table tbody tr", text: /oldest@example\.com/, count: 0
    assert_select "table tbody tr", text: /#{Regexp.escape(t("submissions_list.not_delivered"))}/, count: 1

    get admin_form_submissions_path(form, page: 2)
    assert_select "table tbody tr", count: 1
    assert_select "table tbody tr", text: /oldest@example\.com/
    assert_select "table tbody tr a[href='#{admin_form_submission_path(form, oldest)}']"
    assert in_trash
  end

  test "a form with none says so, in the words of keeping or not" do
    sign_in_as users(:two)
    get admin_form_submissions_path(forms(:newsletter))
    assert_select "[data-empty-state-title]", text: t("submissions_list.empty.title")
    assert_select "button", text: t("submissions_list.delete_all"), count: 0

    get admin_form_submissions_path(forms(:contact))
    assert_select "p", text: t("submissions_list.not_kept")
    assert_select "[data-empty-state-title]", text: t("submissions_list.empty_not_kept.title")
  end

  test "it is a 403 without form_submissions.view, and a submission of another form is a 404" do
    record = submission(forms(:contact))

    sign_in_as users(:reader)
    get admin_form_submissions_path(forms(:contact))
    assert_response :forbidden
    get admin_form_submission_path(forms(:contact), record)
    assert_response :forbidden
    post resend_admin_form_delivery_path(delivery(record, :failed))
    assert_response :forbidden

    sign_in_as submissions_viewer
    get admin_form_submission_path(forms(:newsletter), record)
    assert_response :not_found
    get admin_form_submission_path(forms(:contact), record)
    assert_response :ok

    Current.set(actor: users(:one)) { assert Trash::Move.call(forms(:contact)).ok? }
    get admin_form_submissions_path(forms(:contact))
    assert_response :not_found
    get admin_form_submission_path(forms(:contact), record)
    assert_response :not_found
  end

  test "a viewer with only form_submissions.view who opens a form lands on its submissions, with no tabs" do
    sign_in_as submissions_viewer
    get admin_form_path(forms(:contact))
    assert_redirected_to admin_form_submissions_path(forms(:contact))
    follow_redirect!
    assert_response :ok
    assert_select "a[href='#{admin_form_path(forms(:contact))}']", count: 0

    get admin_forms_path
    assert_select "table tbody tr a[href='#{admin_form_submissions_path(forms(:contact))}']"
  end

  test "the forms list links each form's submissions for a holder of form_submissions.view" do
    sign_in_as users(:two)
    get admin_forms_path
    assert_select "table tbody tr a[href='#{admin_form_path(forms(:contact))}']", text: "Contact"
    assert_select "table tbody tr a[href='#{admin_form_submissions_path(forms(:contact))}']"

    get admin_form_path(forms(:contact))
    assert_select "nav a[aria-current='page']", text: t("tabs.form")
    assert_select "nav a[href='#{admin_form_submissions_path(forms(:contact))}']", text: t("tabs.submissions")
  end

  test "a submission opens with its answers as sent and each destination's result" do
    form = forms(:contact)
    page = create_page(title: "Contact us")
    record = submission(form, page: page)
    sent = delivery(record, :sent)
    waiting = delivery(record, :waiting)
    failed = delivery(record, :failed, key: "not_ready")

    sign_in_as submissions_viewer
    get admin_form_submission_path(form, record)
    assert_response :ok
    assert_select "a[href='#{admin_form_submissions_path(form)}']", text: t("submission.back")
    assert_select "h1", text: t("submission.title")
    assert_select "p", text: /English · from Contact us/
    assert_select "dl dt", text: "Your name"
    assert_select "dl dd", text: ANSWER
    assert_select "dl dd a[href='mailto:#{ADDRESS}']", text: ADDRESS
    assert_select "[data-delivery-state='sent']", text: /#{t("submission.sent")}/i
    assert_select "[data-delivery-state='waiting']", text: /#{t("submission.waiting")}/i
    assert_select "[data-delivery-state='failed'] [data-failure]", text: t("submission.reasons.not_ready")
    assert_select "[data-delivery-state]", text: /#{Regexp.escape(t("submission.mail_to", recipients: "office@example.com"))}/, count: 3
    assert_select "button", text: t("submission.delete_button"), count: 0
    assert [ sent, waiting ].all?(&:persisted?)

    assert_enqueued_with(job: Forms::DeliveryJob, args: [ failed ]) do
      post resend_admin_form_delivery_path(failed)
    end
    assert_redirected_to admin_form_submission_path(form, record)
    assert_equal I18n.t("admin.form_deliveries.resend.sending"), flash[:notice]
    assert failed.reload.waiting?
    follow_redirect!
    assert_select "[data-delivery-state='waiting']", count: 2

    post resend_admin_form_delivery_path(sent)
    assert_redirected_to admin_form_submission_path(form, record)
    assert_equal Forms::Resend.sentence(:not_failed), flash[:alert]
  end

  test "delete and delete all need forms.manage, ask first, and write the event with no answer" do
    form = forms(:contact)
    first, second, third = Array.new(3) { |n| submission(form, age: n.minutes + 1.minute) }

    sign_in_as submissions_viewer
    assert_no_difference -> { Forms::Submission.count } do
      delete admin_form_submission_path(form, first)
      assert_response :forbidden
      delete destroy_all_admin_form_submissions_path(form)
      assert_response :forbidden
    end
    get admin_form_submissions_path(form)
    assert_select "button", text: t("submissions_list.delete_all"), count: 0

    sign_in_as users(:two)
    get admin_form_submission_path(form, first)
    assert_select "dialog", text: /#{Regexp.escape(t("submission.dialog_title"))}/ do
      assert_select "form[action='#{admin_form_submission_path(form, first)}'] button", text: t("submission.confirm")
    end
    delete admin_form_submission_path(forms(:newsletter), first)
    assert_response :not_found
    delete admin_form_submission_path(form, first)
    assert_redirected_to admin_form_submissions_path(form)
    assert_equal I18n.t("admin.form_submissions.destroy.deleted"), flash[:notice]
    assert_not Forms::Submission.exists?(first.id)

    get admin_form_submissions_path(form)
    assert_select "dialog", text: /#{Regexp.escape(t("submissions_list.dialog.title", count: 2, name: "Contact"))}/ do
      assert_select "form[action='#{destroy_all_admin_form_submissions_path(form)}'] button", text: t("submissions_list.dialog.confirm", count: 2)
    end
    delete destroy_all_admin_form_submissions_path(form)
    assert_redirected_to admin_form_submissions_path(form)
    assert_equal I18n.t("admin.form_submissions.destroy_all.deleted", count: 2), flash[:notice]
    assert_equal 0, form.submissions.count
    assert [ second, third ].none? { |record| Forms::Submission.exists?(record.id) }

    Audit::Event.where(action: "form_submissions.deleted").find_each do |event|
      assert_equal "editor", event.metadata["reason"]
      assert_not_includes event.attributes.to_json, ANSWER
      assert_not_includes event.attributes.to_json, ADDRESS
    end
  end

  test "a submission that can't be decrypted is listed as Can't be read, opens with that sentence, and can be deleted" do
    form = forms(:contact)
    other = ActiveRecord::Encryption::DerivedSecretKeyProvider.new("keys that are not the site's")
    record = ActiveRecord::Encryption.with_encryption_context(key_provider: other) { submission(form) }

    sign_in_as users(:two)
    get admin_form_submissions_path(form)
    assert_select "table tbody tr", text: /#{Regexp.escape(t("submissions_list.unreadable"))}/, count: 1
    get admin_form_submission_path(form, record)
    assert_response :ok
    assert_select "p", text: t("submission.unreadable")
    delete admin_form_submission_path(form, record)
    assert_redirected_to admin_form_submissions_path(form)
    assert_not Forms::Submission.exists?(record.id)
  end

  test "no answer appears in a URL or a log line of these requests" do
    form = forms(:contact)
    record = submission(form)
    failed = delivery(record, :failed)
    other = submission(form)

    sign_in_as users(:two)
    log = capture_log(REQUEST_LOGGERS) do
      get admin_form_submissions_path(form)
      assert_response :ok
      css_select("a[href], form[action]").each do |node|
        url = node["href"] || node["action"]
        assert_not_includes url, ANSWER.split.first
        assert_not_includes url, "ada%40"
      end
      get admin_form_submission_path(form, record)
      assert_response :ok
      post resend_admin_form_delivery_path(failed)
      delete admin_form_submission_path(form, other)
      delete destroy_all_admin_form_submissions_path(form)
    end

    assert_includes log, "FormSubmissionsController", "the capture saw the requests"
    [ ANSWER, "Lovelace", ADDRESS, "Hello" ].each { |text| assert_not_includes log, text }
  end
end
