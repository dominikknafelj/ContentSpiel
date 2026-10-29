require "test_helper"

class InvitesMailerTest < ActionMailer::TestCase
  SITE = "https://docs.example.org".freeze
  TOKEN = "tok-en_123456".freeze

  setup do
    @user = users(:one)
    @inviter = users(:two)
  end

  # Built inside the block, and rendered there (`.message`): a mail is lazy,
  # and the address is read when it is built.
  def invite(**) = with_site_address(SITE) { InvitesMailer.invite(@user, inviter: @inviter, token: TOKEN, **).message }

  test "subject and body are the keys' words with the site and the inviter" do
    mail = invite
    name = PersonName.of(@inviter)
    date = I18n.l(7.days.from_now.to_date, format: :long)

    assert_equal "#{name} invited you to Test Site", mail.subject
    assert_equal [ @user.email_address ], mail.to
    [ mail.text_part, mail.html_part ].each do |part|
      body = Nokogiri::HTML5(part.body.to_s).text
      assert_includes body, "#{name} invited you to work on Test Site in Content Spiel. Set a password to finish your account:"
      assert_includes body, "This link works until #{date}. If you weren't expecting this, ignore this mail."
      assert_includes body, "Sent by Test Site via Content Spiel"
    end
  end

  test "the link keeps its token in the fragment, as a button and whole in plain text" do
    mail = invite
    link = "#{SITE}/invitation##{TOKEN}"

    assert_includes mail.text_part.body.to_s, link
    html = Nokogiri::HTML5(mail.html_part.body.to_s)
    assert_equal link, html.at_css("a")["href"]
    assert_equal "Set password", html.at_css("a").text
    assert_includes html.text, link
    assert_equal "/invitation", URI.parse(link).path
    assert_nil URI.parse(link).query
    assert_includes mail.html_part.body.to_s, "max-width:560px"
    assert_no_match(/<img/, mail.html_part.body.to_s)
  end

  test "the link follows the reset's origin rules: the site's address wins, none known sends nothing" do
    with_site_address(nil) do
      mail = InvitesMailer.invite(@user, inviter: @inviter, token: TOKEN, origin: "http://localhost:3000").message
      assert_includes mail.text_part.body.to_s, "http://localhost:3000/invitation##{TOKEN}"
    end
    with_site_address(SITE) do
      mail = InvitesMailer.invite(@user, inviter: @inviter, token: TOKEN, origin: "http://evil.example").message
      assert_not_includes mail.encoded, "evil.example"
    end
    # Production: the request's origin is not used (`request_origin_used?`).
    with_singleton_override(InvitesMailer, :request_origin_used?, ->(*) { false }) do
      with_site_address(nil) do
        assert_no_emails { InvitesMailer.invite(@user, inviter: @inviter, token: TOKEN, origin: "http://evil.example").deliver_now }
      end
    end
  end
end
