require "test_helper"

class SystemMailerTest < ActionMailer::TestCase
  test "subject and body are the keys' words with the site's name" do
    mail = SystemMailer.test_mail(users(:one)).message

    assert_equal "Test mail from Test Site", mail.subject
    assert_equal [ users(:one).email_address ], mail.to
    assert_includes mail.text_part.body.to_s, "Mail from Content Spiel works."
    assert_includes mail.html_part.body.to_s, "Mail from Content Spiel works."
  end

  test "both parts: one column of at most 560px, the site's name as text, the footer, no image or tracking" do
    mail = SystemMailer.test_mail(users(:one)).message
    html = mail.html_part.body.to_s

    assert_includes html, "max-width:560px"
    assert_includes Nokogiri::HTML5(html).text, "Test Site"
    assert_includes mail.text_part.body.to_s, "Sent by Test Site via Content Spiel"
    assert_includes html, "Sent by Test Site via Content Spiel"
    assert_no_match(/<img|<link|url\(/, html)
  end
end
