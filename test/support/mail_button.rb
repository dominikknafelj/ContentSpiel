# The look of a mail's one button (`mails/_button`), held alike for every
# mail that has one: the violet with white words, an 8px radius and no
# shadow, and the whole address in plain text in the line after it.
#
# A failure says what differs and never prints the link: the reset's and
# the invitation's carry a token, which no test output may show.
module MailButton
  BUTTON_STYLE = "display:inline-block;padding:12px 20px;background:#6236d9;color:white;text-decoration:none;border-radius:8px;font-weight:600;".freeze
  ADDRESS_STYLE = "margin:0 0 24px;font-size:13px;color:dimgray;word-break:break-all;".freeze

  def assert_mail_button(html_body)
    html = Nokogiri::HTML5(html_body)
    link = html.css("a")
    assert_equal 1, link.size, "one link in the mail"
    link = link.first
    assert_equal BUTTON_STYLE, link["style"], "the button is the violet with white words and an 8px radius"
    assert_not_includes link["style"], "shadow"

    address = link.parent.next_element
    assert_equal "p", address&.name, "the address is the paragraph after the button"
    assert_equal ADDRESS_STYLE, address["style"], "the address stays dimgray text"
    assert address.text.strip == link["href"], "the address under the button is the link's whole href, as text"
  end
end
