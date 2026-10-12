require "test_helper"

# Where the link in the reset mail points (safe-address spec, "Mail"). The
# site's configured address when there is one, whatever the request said;
# without one, and outside production only, the origin of the request that
# asked, which the controller hands over; otherwise no mail at all and one
# log line. The mail is delivered by a job, so the origin travels as a plain
# string.
class PasswordsMailerTest < ActionMailer::TestCase
  SITE = "https://docs.example.org".freeze
  NOT_SENT = "[ContentSpiel] A password reset mail was not sent: no site address is known. Set PUBLIC_HOST.".freeze

  setup { @user = users(:one) }

  test "with an address configured the link starts with it, whatever origin the request had" do
    with_site_address(SITE) do
      mail = PasswordsMailer.reset(@user, origin: "http://evil.example:8080")

      assert_equal [ @user.email_address ], mail.to
      links_of(mail).each { |link| assert_operator link, :start_with?, "#{SITE}/cs-studio/password/" }
      assert_not_includes mail.encoded, "evil.example"
      assert_not_includes mail.encoded, "8080"
    end
  end

  test "with no address configured the link starts with the origin handed over" do
    with_site_address(nil) do
      mail = PasswordsMailer.reset(@user, origin: "http://localhost:3000")

      links_of(mail).each { |link| assert_operator link, :start_with?, "http://localhost:3000/cs-studio/password/" }
    end
  end

  # IN PRODUCTION THE REQUEST'S ORIGIN IS NEVER USED. It is whatever Host the
  # request named, and a production site with no address configured answers
  # every host: a reset asked for under a made-up one would mail the account's
  # owner a valid token on a link to that host.
  test "in production with no address configured no mail is built, whatever origin is handed over, and the log says why" do
    in_production do
      with_site_address(nil) do
        [ "http://evil.example", "http://localhost:3000", nil ].each do |origin|
          log = capture_log do
            assert_no_emails { PasswordsMailer.reset(@user, origin: origin).deliver_now }
          end

          assert_equal [ NOT_SENT ], log.lines.map(&:strip).grep(/ContentSpiel/), origin.inspect
          assert_not_includes log, "evil.example"
          assert_no_token_in log
        end
        assert_empty ActionMailer::Base.deliveries
      end
    end
  end

  test "in production with an address configured the link is the address's, whatever origin says" do
    in_production do
      with_site_address(SITE) do
        mail = PasswordsMailer.reset(@user, origin: "http://evil.example")

        links_of(mail).each { |link| assert_operator link, :start_with?, "#{SITE}/cs-studio/password/" }
        assert_not_includes mail.encoded, "evil.example"
      end
    end
  end

  test "the request's origin is used in development and in test, and not in production" do
    assert PasswordsMailer.request_origin_used?(ActiveSupport::EnvironmentInquirer.new("development"))
    assert PasswordsMailer.request_origin_used?(ActiveSupport::EnvironmentInquirer.new("test"))
    assert_not PasswordsMailer.request_origin_used?(ActiveSupport::EnvironmentInquirer.new("production"))
    assert PasswordsMailer.request_origin_used?, "this suite runs in test, where it is used"
  end

  # The environments' own `default_url_options` are literals (a port in
  # development, example.com in test): an option the address does not set
  # must not be filled in from them.
  test "nothing of the environment's default url options reaches the link" do
    with_default_url_options(host: "literal.example", port: 3000, protocol: "http") do
      with_site_address(SITE) do
        links_of(PasswordsMailer.reset(@user)).each { |link| assert_operator link, :start_with?, "#{SITE}/cs-studio/password/" }
      end
      with_site_address(nil) do
        links_of(PasswordsMailer.reset(@user, origin: "https://staging.example.org")).each do |link|
          assert_operator link, :start_with?, "https://staging.example.org/cs-studio/password/"
        end
      end
    end
  end

  test "both parts carry the same link, and it opens the reset form's route" do
    with_site_address(SITE) do
      text, html = links_of(PasswordsMailer.reset(@user))

      assert_equal text, html
      assert_equal @user, User.find_by_password_reset_token!(URI.parse(text).path.delete_prefix("/cs-studio/password/").delete_suffix("/edit"))
    end
  end

  test "with neither an address nor an origin no mail is delivered, and the log says why without a token" do
    with_site_address(nil) do
      log = capture_log do
        assert_no_emails { PasswordsMailer.reset(@user).deliver_now }
      end

      assert_equal [ NOT_SENT ], log.lines.map(&:strip).grep(/ContentSpiel/)
      assert_no_token_in log
    end
  end

  # The origin is the request's, so it is whatever Host a client sent: one
  # that is not an origin is no origin, and nothing of it is logged.
  test "an origin that is not an origin is no origin: no mail, the same line, and the value is not repeated" do
    with_site_address(nil) do
      [ "http://user:hunter2@evil.example", "evil.example", "javascript:alert(1)", "http://evil.example/\nX-Injected: 1", "http://a b" ].each do |origin|
        log = capture_log do
          assert_no_emails { PasswordsMailer.reset(@user, origin: origin).deliver_now }
        end

        assert_equal [ NOT_SENT ], log.lines.map(&:strip).grep(/ContentSpiel/), origin.inspect
        assert_not_includes log, "evil.example"
        assert_not_includes log, "hunter2"
        assert_no_token_in log
      end
    end
  end

  test "an origin with a path or a query contributes its origin only" do
    with_site_address(nil) do
      links_of(PasswordsMailer.reset(@user, origin: "http://localhost:3000/somewhere?x=1")).each do |link|
        assert_operator link, :start_with?, "http://localhost:3000/cs-studio/password/"
      end
    end
  end

  test "the origin survives the job: delivered later, the link still starts with it" do
    with_site_address(nil) do
      perform_enqueued_jobs { PasswordsMailer.reset(@user, origin: "http://localhost:3000").deliver_later }

      links_of(ActionMailer::Base.deliveries.sole).each { |link| assert_operator link, :start_with?, "http://localhost:3000/cs-studio/password/" }
    end
  end

  private

  # The link of the text part and of the HTML part, in that order.
  def links_of(mail)
    text = mail.text_part.body.to_s[%r{https?://\S+}]
    html = Nokogiri::HTML5.fragment(mail.html_part.body.to_s).at_css("a")["href"]
    [ text, html ].each { |link| assert link.present?, "a part of the mail has no link" }
  end

  def in_production(&)
    with_singleton_override(PasswordsMailer, :request_origin_used?, ->(*) { false }, &)
  end

  def with_default_url_options(options)
    was = ActionMailer::Base.default_url_options
    ActionMailer::Base.default_url_options = options
    yield
  ensure
    ActionMailer::Base.default_url_options = was
  end

  def capture_log
    was = Rails.logger
    io = StringIO.new
    Rails.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = was
  end

  # A reset token is a signed message: a long run of URL-safe characters.
  def assert_no_token_in(log)
    assert_no_match(/[A-Za-z0-9_=-]{40,}/, log)
    assert_not_includes log, @user.email_address
  end
end
