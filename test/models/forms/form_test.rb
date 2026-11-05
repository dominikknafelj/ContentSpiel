require "test_helper"

# A form: its own trashable record, whose texts are
# translated values that fall back to the default language and whose keeping
# depends on the site having encryption keys.
class Forms::FormTest < ActiveSupport::TestCase
  test "a form keeps only where it says and where the site has encryption keys" do
    assert forms(:newsletter).keeps?
    assert_not forms(:contact).keeps?

    with_singleton_override(Forms::Encryption, :available?, -> { false }) do
      assert_not forms(:newsletter).keeps?
    end
  end

  test "Forms::Encryption says whether the site has its keys, and a site without them has none" do
    assert Forms::Encryption.available?
    without_encryption_keys { assert_not Forms::Encryption.available? }
    assert Forms::Encryption.available?, "asked again afterwards, in test it is not memoised"
  end

  test "effective_keep_days is the form's days, else the site's, else nil when it does not keep" do
    assert_equal 90, Current.site.form_keep_days, "the site's default"
    assert_equal 30, forms(:newsletter).effective_keep_days

    following = forms(:newsletter)
    following.keep_days = nil
    assert_equal 90, following.effective_keep_days
    Current.site.form_keep_days = 45
    assert_equal 45, following.effective_keep_days

    assert_nil forms(:contact).effective_keep_days
    with_singleton_override(Forms::Encryption, :available?, -> { false }) do
      assert_nil forms(:newsletter).effective_keep_days, "a form that cannot keep keeps for no days"
    end
  end

  test "submit label and thank-you fall back to the default language" do
    with_locales(%w[en de], default: "en") do
      form = forms(:contact)
      assert_equal "Send", form.submit_label_in("de")
      assert_equal "Thank you, we'll be in touch.", form.thank_you_in("de")

      Mobility.with_locale(:de) { form.submit_label = "Senden" }
      assert_equal "Senden", form.submit_label_in("de")
      assert_equal "Send", form.submit_label_in("en")

      assert_nil forms(:newsletter).thank_you_in("de"), "nil when blank: the public key fills in"
    end
  end

  test "fields are the stored list as Forms::Field values, in their order" do
    fields = forms(:newsletter).fields

    assert(fields.all?(Forms::Field))
    assert_equal %w[f_mail0002 f_topic002 f_okay0002], fields.map(&:key)
    assert_equal %w[News Offers], fields.second.choices.map { |choice| choice.label_in("en") }
  end

  test "destinations come in their order, and a form is trashable" do
    assert_equal [ form_destinations(:contact_mail) ], forms(:contact).destinations.to_a
    assert_empty forms(:newsletter).destinations

    assert_includes Forms::Form.kept, forms(:contact)
    forms(:contact).update_columns(trashed_at: Time.current)
    assert_equal [ forms(:contact) ], Forms::Form.trashed.to_a
  end
end
