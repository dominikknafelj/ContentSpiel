require "test_helper"

# The submissions list's one line about a submission (forms plan, decision
# 7): computed from the decrypted answers, never stored. The first two
# answers of the types that say `summary` (short text and email), joined
# and cut at 80 characters; nil for none and for a submission the keys can
# no longer read.
class Forms::SummaryTest < ActiveSupport::TestCase
  def row(key, type, value, display: value) = { "key" => key, "type" => type, "label" => key, "value" => value, "display" => display }

  def submission(*rows, form: forms(:contact)) = Forms::Submission.create!(form: form, locale: "en", answers: rows)

  test "the first two short-text or email answers, joined and cut at 80" do
    two = submission(row("a", "short_text", "Ada Lovelace"), row("b", "long_text", "A long message"),
      row("c", "email", "ada@example.com"), row("d", "short_text", "A third one"))
    assert_equal "Ada Lovelace · ada@example.com", Forms::Summary.of(two)

    blank_first = submission(row("a", "short_text", ""), row("b", "short_text", nil, display: ""), row("c", "email", "bea@example.com"))
    assert_equal "bea@example.com", Forms::Summary.of(blank_first), "an answer left empty is skipped"

    long = submission(row("a", "short_text", "x" * 70), row("b", "email", "#{"y" * 30}@example.com"))
    summary = Forms::Summary.of(long)
    assert_equal Forms::Summary::LIMIT, summary.length
    assert summary.start_with?("x" * 70)
    assert summary.end_with?("…")
  end

  test "a long text, a choice and a checkbox are not in it" do
    record = submission(row("a", "long_text", "Hello there"), row("b", "choice", "c_news0001", display: "News"),
      row("c", "checkbox", true, display: "Yes"), form: forms(:newsletter))
    assert_nil Forms::Summary.of(record)

    unknown = submission(row("a", "acme/rating", "5"), row("b", "email", "cy@example.com"))
    assert_equal "cy@example.com", Forms::Summary.of(unknown), "a type no longer registered is not summarised"
  end

  test "a submission the keys can't read has no summary" do
    record = submission(row("a", "short_text", "Ada"))
    other = ActiveRecord::Encryption::DerivedSecretKeyProvider.new("keys that are not the site's")
    ActiveRecord::Encryption.with_encryption_context(key_provider: other) do
      assert_nil Forms::Summary.of(Forms::Submission.find(record.id))
    end
  end
end
