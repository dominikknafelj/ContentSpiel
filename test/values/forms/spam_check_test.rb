require "test_helper"

# The two spam measures that are a form's own (forms spec, "Sending"): the
# honeypot `website`, which a person never sees, and the signed draw time.
# A trip is named; a clean send is nil. The rate limit is the controller's
# (`Forms::SendLimit`).
class Forms::SpamCheckTest < ActiveSupport::TestCase
  include FormSends

  test "a filled honeypot, a send under 3 seconds and a bad token are each spam, and a clean send is not" do
    form = forms(:contact)
    now = Time.current
    clean = { "drawn" => aged_drawn(form), "website" => "" }

    assert_nil Forms::SpamCheck.call(clean, form: form, now: now)
    assert_nil Forms::SpamCheck.call(clean.except("website"), form: form, now: now)
    assert_nil Forms::SpamCheck.call(ActionController::Parameters.new(clean), form: form, now: now)

    assert_equal :honeypot, Forms::SpamCheck.call(clean.merge("website" => "https://spam.example"), form: form, now: now)
    assert_equal :honeypot, Forms::SpamCheck.call(clean.merge("website" => [ "x" ]), form: form, now: now)
    assert_equal :too_soon, Forms::SpamCheck.call(clean.merge("drawn" => Forms::Drawn.token(form, at: now - 1)), form: form, now: now)
    assert_equal :invalid_token, Forms::SpamCheck.call(clean.merge("drawn" => "made-up"), form: form, now: now)
    assert_equal :invalid_token, Forms::SpamCheck.call(clean.except("drawn"), form: form, now: now)
    assert_equal :invalid_token, Forms::SpamCheck.call(clean.merge("drawn" => aged_drawn(forms(:newsletter))), form: form, now: now)
  end
end
