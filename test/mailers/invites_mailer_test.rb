require "test_helper"

class InvitesMailerTest < ActionMailer::TestCase
  include LogCapture
  SITE = "https://docs.example.org".freeze

  setup do
    @inviter = users(:two)
    @invitation = open_invitation("dana@example.com", inviter: @inviter)
  end

  # Built inside the block, and rendered there (`.message`): a mail is lazy,
  # and the address is read when it is built.
  def invite(**) = with_site_address(SITE) { InvitesMailer.invite(@invitation, **).message }

  test "subject and body are the keys' words with the site and the inviter" do
    mail = invite
    name = PersonName.of(@inviter)
    date = I18n.l(7.days.from_now.to_date, format: :long)

    assert_equal "#{name} invited you to Test Site", mail.subject
    assert_equal [ "dana@example.com" ], mail.to
    [ mail.text_part, mail.html_part ].each do |part|
      body = Nokogiri::HTML5(part.body.to_s).text
      assert_includes body, "#{name} invited you to work on Test Site in Content Spiel. Set a password to finish your account:"
      assert_includes body, "This link works until #{date}. If you weren't expecting this, ignore this mail."
      assert_includes body, "Sent by Test Site via Content Spiel"
    end
  end

  test "the link keeps its token in the fragment, as a button and whole in plain text" do
    mail = invite
    link = html_link(mail)
    assert_match %r{\A#{SITE}/cs-studio/invitation#\S+\z}, link

    assert_includes mail.text_part.body.to_s, link
    html = Nokogiri::HTML5(mail.html_part.body.to_s)
    assert_equal link, html.at_css("a")["href"]
    assert_equal @invitation, Invitation.find_by_token_for(:accept, URI.parse(link).fragment), "the fragment is the invitation's token"
    assert_equal "Set password", html.at_css("a").text
    assert_includes html.text, link
    assert_equal "/cs-studio/invitation", URI.parse(link).path
    assert_nil URI.parse(link).query
    assert_includes mail.html_part.body.to_s, "max-width:560px"
    assert_no_match(/<img/, mail.html_part.body.to_s)
  end

  test "the link follows the reset's origin rules: the site's address wins, none known sends nothing" do
    with_site_address(nil) do
      mail = InvitesMailer.invite(@invitation, origin: "http://localhost:3000").message
      assert_includes mail.text_part.body.to_s, "http://localhost:3000/cs-studio/invitation#"
    end
    with_site_address(SITE) do
      mail = InvitesMailer.invite(@invitation, origin: "http://evil.example").message
      assert_not_includes mail.encoded, "evil.example"
    end
    # Production: the request's origin is not used (`request_origin_used?`).
    with_singleton_override(InvitesMailer, :request_origin_used?, ->(*) { false }) do
      with_site_address(nil) do
        assert_no_emails { InvitesMailer.invite(@invitation, origin: "http://evil.example").deliver_now }
      end
    end
  end

  test "the queued job holds no token: its arguments are the invitation's Global ID and an origin" do
    with_site_address(SITE) do
      ApplicationMailer.queue(InvitesMailer, :invite, @invitation)
    end
    job = ActiveJob::Base.queue_adapter.enqueued_jobs.last
    args = job["arguments"].to_json

    assert_includes args, @invitation.to_global_id.to_s
    assert_no_match(/[A-Za-z0-9_=-]{40,}/, args.gsub(/gid:\/\/[\w\/-]+/, "").gsub(/[a-f0-9]{64}/, ""), "no signed token among the arguments")
    assert_nil args[@invitation.generate_token_for(:accept)]
  end

  # Ruling T8a's rule for an invitation that can no longer be accepted: the
  # job sends nothing and says so in one line with no address.
  test "an invitation accepted since it was queued sends nothing" do
    @invitation.update!(accepted_at: Time.current)
    log = capture_log { assert_no_emails { with_site_address(SITE) { InvitesMailer.invite(@invitation).deliver_now } } }
    assert_includes log, "An invitation mail was not sent: the invite is no longer open."
    assert_not_includes log, "dana@example.com"
  end

  test "an invitation whose inviter was deleted is the site's own" do
    @invitation.update!(inviter: nil)
    assert_equal "Test Site invited you to Test Site", invite.subject
  end

  private

  def html_link(mail) = Nokogiri::HTML5(mail.html_part.body.to_s).at_css("a")["href"]
end
