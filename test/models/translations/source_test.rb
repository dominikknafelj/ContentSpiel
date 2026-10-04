require "test_helper"

class Translations::SourceTest < ActiveSupport::TestCase
  test "an old entry is a bare digest: no text, no time" do
    source = Translations::Source.wrap("abc123")
    assert_equal "abc123", source.digest
    assert_nil source.text
    assert_nil source.saved_at
    assert_not source.stored_text?
  end

  test "a new entry carries digest, text and when it was saved" do
    source = Translations::Source.wrap("digest" => "abc", "text" => "Hello world", "saved_at" => "2026-10-04T09:30:00Z")
    assert_equal "abc", source.digest
    assert_equal "Hello world", source.text
    assert_equal Time.utc(2026, 10, 4, 9, 30), source.saved_at
    assert source.stored_text?
  end

  test "nothing stored is nil, and junk never raises" do
    assert_nil Translations::Source.wrap(nil)
    assert_nil Translations::Source.wrap("")
    [ 42, [], { "text" => "no digest" }, { "digest" => "d", "saved_at" => "not a time" } ].each do |junk|
      assert_nothing_raised { Translations::Source.wrap(junk)&.saved_at }
    end
    assert_nil Translations::Source.wrap("text" => "no digest")
  end
end
