require "test_helper"

# The signed draw time a Form block carries: a
# send under `MIN_SECONDS` after the form was drawn is too soon, a token of
# another form or one tampered with is no token, and there is no expiry,
# because a cached page keeps an old token, which only makes it older.
class Forms::DrawnTest < ActiveSupport::TestCase
  test "a token is ok after 3 seconds and too_soon before" do
    form = forms(:contact)
    now = Time.current
    token = Forms::Drawn.token(form, at: now)

    assert_equal 3, Forms::Drawn::MIN_SECONDS
    assert_equal :too_soon, Forms::Drawn.check(token, form: form, now: now)
    assert_equal :too_soon, Forms::Drawn.check(token, form: form, now: now + 2)
    assert_equal :ok, Forms::Drawn.check(token, form: form, now: now + 3)
    assert_equal :ok, Forms::Drawn.check(token, form: form, now: now + 60)
  end

  test "a token of another form, or tampered, is invalid" do
    contact = forms(:contact)
    token = Forms::Drawn.token(contact, at: 1.minute.ago)

    assert_equal :invalid, Forms::Drawn.check(token, form: forms(:newsletter))
    assert_equal :invalid, Forms::Drawn.check("#{token}x", form: contact)
    assert_equal :invalid, Forms::Drawn.check(token.reverse, form: contact)
    assert_equal :invalid, Forms::Drawn.check("", form: contact)
    assert_equal :invalid, Forms::Drawn.check(nil, form: contact)
    assert_equal :invalid, Forms::Drawn.check({ "t" => 1 }, form: contact)

    # A token signed for something else with the same secret is no draw time.
    other = Rails.application.message_verifier("another purpose").generate({ "f" => contact.id, "t" => 1.minute.ago.to_i })
    assert_equal :invalid, Forms::Drawn.check(other, form: contact)
  end

  test "a token has no expiry: one drawn a week ago is ok" do
    form = forms(:contact)
    assert_equal :ok, Forms::Drawn.check(Forms::Drawn.token(form, at: 1.week.ago), form: form)
  end
end
