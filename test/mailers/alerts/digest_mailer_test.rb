require "test_helper"

# The owners' digest: what it says of each alert, how many it lists, where
# its one link points, and that nothing of an error's message, or an
# address, reaches it.
class Alerts::DigestMailerTest < ActionMailer::TestCase
  include ActiveJob::TestHelper
  include MailButton

  SITE = "https://docs.example.org".freeze
  SEEN = Time.utc(2026, 11, 16, 12, 47)

  setup do
    Alerts::Alert.delete_all
    @owner = users(:one)
    SiteSetting.instance.update_columns(time_zone: "Europe/Berlin")
  end

  def make(kind, seen: SEEN, occurrences: 1, **details)
    Alerts::Alert.create!(kind: kind, fingerprint: SecureRandom.hex(8), details: details, occurrences: occurrences,
                          first_seen_at: seen, last_seen_at: seen)
  end

  # Built and rendered inside the block: the address is read when it is built.
  def digest(ids) = with_site_address(SITE) { Alerts::DigestMailer.digest(@owner, ids).message }

  def bodies(mail) = [ mail.text_part, mail.html_part ].map { Nokogiri::HTML5(it.body.to_s).text.squeeze(" ") }

  test "two alerts: the subject, the intro, a line per alert with its kind, sentence and facts, the footer" do
    error = make("error", occurrences: 12, error_class: "NoMethodError", place: "app/models/page.rb:120")
    owner = make("owner_changed", seen: SEEN - 1.hour, subject_label: "Ana Example", actor_name: nil, now_owner: true)

    mail = digest([ owner.id, error.id ])

    assert_equal "2 alerts on Test Site", mail.subject
    assert_equal [ @owner.email_address ], mail.to
    bodies(mail).each do |body|
      assert_includes body, "2 alerts on Test Site since the last mail:"
      assert_includes body, "Error: NoMethodError in app/models/page.rb:120"
      # 12:47 UTC is 13:47 in Berlin, in November.
      assert_includes body, "12 times · last 16 Nov 2026, 13:47"
      assert_includes body, "Security: Ana Example was made an owner"
      assert_includes body, "Once · last 16 Nov 2026, 12:47"
      assert_includes body, "You get this mail as an owner of Test Site. At most one mail every 10 minutes."
      assert_includes body, "Sent by Test Site via Content Spiel"
      assert body.index("NoMethodError") < body.index("Ana Example"), "newest first"
    end
  end

  test "one alert: the subject and the intro say one" do
    mail = digest([ make("token_issued", token_name: "deploy", group_name: "Editors", actor_name: "Ben").id ])

    assert_equal "1 alert on Test Site", mail.subject
    bodies(mail).each do |body|
      assert_includes body, "1 alert on Test Site since the last mail:"
      assert_includes body, "Security: API token “deploy” issued by Ben"
    end
  end

  test "each kind reads as a sentence" do
    sentences = {
      make("error", error_class: "RuntimeError", place: nil) => "Error: RuntimeError",
      make("sign_in_failures", failed: 23, locked: 1) => "Security: 23 failed sign-ins in 15 minutes",
      make("owner_changed", subject_label: "Ana", actor_name: "Ben", now_owner: true) => "Security: Ana was made an owner by Ben",
      make("owner_changed", subject_label: "Ana", actor_name: nil, now_owner: false) => "Security: Ana is no longer an owner",
      make("owner_changed", subject_label: "Ana", actor_name: "Ben", now_owner: false) => "Security: Ana is no longer an owner, by Ben",
      make("token_issued", token_name: "deploy", group_name: "Editors", actor_name: nil) => "Security: API token “deploy” issued",
      make("access_denied_burst", denied: 25, actors: 2) => "Security: 25 actions refused in 15 minutes, by 2 accounts",
      make("request_limited", limited: 1, limits: [ "sign_in" ]) => "Security: A limit on requests was reached once in 15 minutes: sign_in",
      make("request_limited", limited: 3, limits: %w[default sign_in]) => "Security: Limits on requests were reached 3 times in 15 minutes: default, sign_in"
    }

    mail = digest(sentences.keys.map(&:id))
    bodies(mail).each do |body|
      sentences.each_value { |line| assert_includes body, line }
    end
  end

  test "21 alerts list 20 and say one more" do
    alerts = 21.times.map { |i| make("error", seen: SEEN - i.minutes, error_class: "Error#{i}Class", place: nil) }

    mail = digest(alerts.map(&:id))
    assert_equal "21 alerts on Test Site", mail.subject
    bodies(mail).each do |body|
      assert_includes body, "Error0Class"
      assert_includes body, "Error19Class"
      assert_not_includes body, "Error20Class"
      assert_includes body, "and 1 more"
    end
  end

  test "the button and the plain address are System status on the link origin" do
    mail = digest([ make("error", error_class: "RuntimeError", place: nil).id ])

    html = Nokogiri::HTML5(mail.html_part.body.to_s)
    assert_equal "#{SITE}/cs-studio/system_status", html.at_css("a")["href"]
    assert_equal "Open System status", html.at_css("a").text
    assert_includes mail.text_part.body.to_s, "#{SITE}/cs-studio/system_status"
    assert_mail_button(mail.html_part.body.to_s)
  end

  test "an alert deleted before delivery is skipped, and with none left no mail is built" do
    kept = make("error", error_class: "KeptError", place: nil)
    gone = make("error", error_class: "GoneError", place: nil)
    gone.destroy!

    mail = digest([ kept.id, gone.id ])
    assert_equal "1 alert on Test Site", mail.subject
    assert_not_includes mail.text_part.body.to_s, "GoneError"

    kept.destroy!
    assert_no_emails { with_site_address(SITE) { Alerts::DigestMailer.digest(@owner, [ kept.id, gone.id ]).deliver_now } }
  end

  test "with no address to link to no mail is built" do
    with_singleton_override(Alerts::DigestMailer, :request_origin_used?, ->(*) { false }) do
      with_site_address(nil) do
        id = make("error", error_class: "RuntimeError", place: nil).id
        assert_no_emails { Alerts::DigestMailer.digest(@owner, [ id ]).deliver_now }
      end
    end
  end

  test "an error's message and an address never reach the mail" do
    error = begin
      raise RuntimeError, "password=hunter2 from 203.0.113.9"
    rescue RuntimeError => raised
      raised
    end
    perform_enqueued_jobs do
      with_error_alerts { Rails.error.report(error, source: "application.action_dispatch") }
    end
    owner = make("owner_changed", subject_label: "Ana", actor_name: "Ben", now_owner: true)

    mail = digest(Alerts::Alert.pluck(:id))
    assert_includes mail.text_part.body.to_s, "RuntimeError in test/mailers/alerts/digest_mailer_test.rb:"
    assert_includes mail.text_part.body.to_s, owner.details["subject_label"]
    [ mail.text_part, mail.html_part ].each do |part|
      assert_not_includes part.body.to_s, "hunter2"
      assert_no_match(/\b\d{1,3}(?:\.\d{1,3}){3}\b/, part.body.to_s)
    end
  end
end
