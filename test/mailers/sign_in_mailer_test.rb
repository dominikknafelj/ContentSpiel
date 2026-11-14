require "test_helper"

# The mail to an account whose sign-in a run of failed attempts paused: what
# it says, and where its one link points (the reset request, which carries
# no token, under the origin the reset's link would have).
class SignInMailerTest < ActionMailer::TestCase
  SITE = "https://docs.example.org".freeze
  NOT_SENT = "[ContentSpiel] A sign-in pause mail was not sent: no site address is known. Set PUBLIC_HOST.".freeze

  include LogCapture
  include MailButton

  setup { @user = users(:one) }

  def locked(minutes: 4, origin: nil, locked_at: Time.utc(2026, 11, 10, 22, 30))
    SignInMailer.locked(@user, locked_at: locked_at, from_address: "203.0.113.7", minutes: minutes, origin: origin)
  end

  test "the lock-out mail names the site, the minutes, the time in the site's zone and the address, and links to the reset request with no token" do
    SiteSetting.instance.update_columns(time_zone: "Europe/Berlin")

    with_site_address(SITE) do
      mail = locked(origin: "http://evil.example")

      assert_equal "Signing in to Test Site is paused", mail.subject
      assert_equal [ @user.email_address ], mail.to
      [ mail.text_part, mail.html_part ].each do |part|
        body = Nokogiri::HTML5(part.body.to_s).text
        assert_includes body, "There were several failed attempts to sign in to your account on Test Site, so signing in is paused for 4 minutes."
        # 22:30 UTC is 23:30 in Berlin, in November.
        assert_includes body, "The last attempt was at 10 Nov 2026, 23:30, from the address 203.0.113.7."
        assert_includes body, "If this was you, wait and try again, or reset your password, which ends the pause. A browser you have signed in with before is not paused. If it wasn't you, your password kept them out, and resetting it is still the safest step."
        assert_includes body, "Sent by Test Site via Content Spiel"
      end

      text_link = mail.text_part.body.to_s[%r{https?://\S+}]
      html = Nokogiri::HTML5(mail.html_part.body.to_s)
      assert_equal "#{SITE}/cs-studio/password/new", text_link
      assert_equal text_link, html.at_css("a")["href"]
      assert_equal "Reset password", html.at_css("a").text
      assert_nil URI.parse(text_link).fragment, "the reset request carries no token"
      assert_not_includes mail.encoded, "evil.example"
      assert_mail_button(mail.html_part.body.to_s)
    end

    with_site_address(nil) do
      mail = locked(minutes: 1, origin: "http://localhost:3000")
      assert_includes mail.text_part.body.to_s, "so signing in is paused for 1 minute."
      assert_includes mail.text_part.body.to_s, "http://localhost:3000/cs-studio/password/new"
    end
  end

  test "with no address known outside development and test no mail is built" do
    with_singleton_override(SignInMailer, :request_origin_used?, ->(*) { false }) do
      with_site_address(nil) do
        log = capture_log do
          assert_no_emails { locked(origin: "http://evil.example").deliver_now }
        end

        assert_equal [ NOT_SENT ], log.lines.map(&:strip).grep(/ContentSpiel/)
        assert_not_includes log, "evil.example"
        assert_not_includes log, @user.email_address
      end
    end
  end

  def passkey_added(origin: "http://localhost:3000", name: "Work laptop")
    SignInMailer.passkey_added(@user, name: name, added_at: Time.utc(2026, 11, 10, 22, 30), origin: origin)
  end

  def recovery_code_used(left:, origin: "http://localhost:3000")
    SignInMailer.recovery_code_used(@user, used_at: Time.utc(2026, 11, 10, 22, 30), from_address: "203.0.113.7", left: left, origin: origin)
  end

  test "passkey_added names the passkey and the time, and links to Your account's passkeys" do
    SiteSetting.instance.update_columns(time_zone: "Europe/Berlin")

    with_site_address(SITE) do
      mail = passkey_added(origin: "http://evil.example")

      assert_equal "A passkey was added to your account on Test Site", mail.subject
      assert_equal [ @user.email_address ], mail.to
      [ mail.text_part, mail.html_part ].each do |part|
        body = Nokogiri::HTML5(part.body.to_s).text
        assert_includes body, "A passkey named \u201CWork laptop\u201D was added to your account on Test Site at 10 Nov 2026, 23:30."
        assert_includes body, "If this wasn't you, remove the passkey there and change your password."
      end

      html = Nokogiri::HTML5(mail.html_part.body.to_s)
      text_link = mail.text_part.body.to_s[%r{https?://\S+}]
      assert_equal "#{SITE}/cs-studio/account#passkeys", text_link
      assert_equal text_link, html.at_css("a")["href"]
      assert_equal "Open Your account", html.at_css("a").text
      assert_not_includes mail.encoded, "evil.example"
      assert_mail_button(mail.html_part.body.to_s)
    end
  end

  test "with an admin host the reset request's and Your account's links name it, and without one the public host" do
    [ [ "https://studio.example.internal", "studio.example.internal" ], [ nil, "docs.example.org" ] ].each do |admin, host|
      with_site_address(SITE) do
        with_admin_address(admin) do
          [ locked(origin: "http://evil.example"), passkey_added, recovery_code_used(left: 3) ].each do |mail|
            link = mail.text_part.body.to_s[%r{https?://\S+}]
            assert_equal host, URI.parse(link).host
            assert_equal host, URI.parse(Nokogiri::HTML5(mail.html_part.body.to_s).at_css("a")["href"]).host
          end
        end
      end
    end
  end

  test "recovery_code_used says the address and how many codes are left, one and many" do
    with_site_address(SITE) do
      one = recovery_code_used(left: 1)
      many = recovery_code_used(left: 7)

      assert_equal "A recovery code was used on Test Site", one.subject
      [ one.text_part, one.html_part ].each do |part|
        assert_includes Nokogiri::HTML5(part.body.to_s).text, "A recovery code was used to sign in to your account on Test Site at 10 Nov 2026, 22:30, from the address 203.0.113.7. 1 code is left."
      end
      [ many.text_part, many.html_part ].each do |part|
        body = Nokogiri::HTML5(part.body.to_s).text
        assert_includes body, "from the address 203.0.113.7. 7 codes are left."
        assert_includes body, "If this wasn't you, regenerate your recovery codes and change your password."
      end
      assert_equal "#{SITE}/cs-studio/account#passkeys", many.text_part.body.to_s[%r{https?://\S+}]
      assert_equal "Open Your account", Nokogiri::HTML5(many.html_part.body.to_s).at_css("a").text
    end
  end

  test "with mail not ready queue_alert queues nothing and its span says so" do
    exporter = Rails.application.config.x.otel_test_exporter
    exporter.reset

    with_mail_state(:not_set_up) do
      queued = nil
      log = capture_log do
        queued = Telemetry.in_span("auth.session", kind: :server) do
          SignInMailer.queue_alert(:passkey_added, @user, name: "Work laptop", added_at: Time.current, origin: SITE)
        end
      end
      assert_equal false, queued
      assert_no_enqueued_jobs
      assert_equal [ "[ContentSpiel] A sign-in account mail (passkey_added) was not queued: mail is not ready." ],
        log.lines.map(&:strip).grep(/ContentSpiel/), "one line, naming nobody"
      assert_not_includes log, "Work laptop"
      assert_not_includes log, @user.email_address
    end

    span = exporter.finished_spans.find { |s| s.name == "auth.account_mail" }
    assert_equal({ "auth.mail.kind" => "passkey_added", "auth.mail.queued" => false }, span.attributes.to_h)

    with_mail_state(:working) do
      queued = Telemetry.in_span("auth.session", kind: :server) do
        SignInMailer.queue_alert(:recovery_code_used, @user, used_at: Time.current, from_address: "203.0.113.7", left: 3, origin: SITE)
      end
      assert_equal true, queued
      assert_enqueued_jobs 1
    end
    span = exporter.finished_spans.select { |s| s.name == "auth.account_mail" }.last
    assert_equal({ "auth.mail.kind" => "recovery_code_used", "auth.mail.queued" => true }, span.attributes.to_h)
  end

  test "a mail without a known origin is not sent and the line names nobody" do
    with_singleton_override(SignInMailer, :request_origin_used?, ->(*) { false }) do
      with_site_address(nil) do
        log = capture_log do
          assert_no_emails do
            passkey_added.deliver_now
            recovery_code_used(left: 2).deliver_now
          end
        end

        lines = log.lines.map(&:strip).grep(/ContentSpiel/)
        assert_equal [ "[ContentSpiel] A sign-in account mail was not sent: no site address is known. Set PUBLIC_HOST." ] * 2, lines
        assert_not_includes log, "Work laptop"
        assert_not_includes log, "203.0.113.7"
        assert_not_includes log, @user.email_address
      end
    end
  end
end
