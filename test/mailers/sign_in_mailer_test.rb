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
        assert_includes body, "If this was you, wait and try again, or reset your password. If it wasn't, your password kept them out, and resetting it is still the safest step."
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
end
