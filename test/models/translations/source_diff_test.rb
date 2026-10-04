require "test_helper"

class Translations::SourceDiffTest < ActiveSupport::TestCase
  def segments(from, to) = Translations::SourceDiff.call(from: from, to: to).segments

  test "a changed word is a delete followed by an insert, the rest equal" do
    assert_equal [ [ :equal, "We started in a " ], [ :delete, "spare" ], [ :insert, "small" ], [ :equal, " room." ] ],
      segments("We started in a spare room.", "We started in a small room.")
  end

  test "added and removed words at the ends" do
    assert_equal [ [ :equal, "Hello" ], [ :insert, " world" ] ], segments("Hello", "Hello world")
    assert_equal [ [ :delete, "Hello " ], [ :equal, "world" ] ], segments("Hello world", "world")
  end

  test "identical text has no changes and is formatting-only when asked about a changed digest" do
    result = Translations::SourceDiff.call(from: "Same text", to: "Same text")
    assert_not result.changed?
    assert result.formatting_only?
  end

  test "paragraph arrays are compared paragraph by paragraph, with added and removed paragraphs whole" do
    result = Translations::SourceDiff.call(from: [ "One.", "Two." ], to: [ "One.", "Two and a half.", "Three." ])
    assert result.changed?
    assert_includes result.segments, [ :insert, "Three." ]
    assert_includes result.segments, [ :equal, "One." ]
  end

  test "nil on either side means nothing to compare" do
    assert_not Translations::SourceDiff.call(from: nil, to: "x").changed?
    assert_empty Translations::SourceDiff.call(from: nil, to: "x").segments
  end

  test "text past the word cap is not diffed" do
    long = Array.new(Translations::SourceDiff::MAX_WORDS + 1, "word").join(" ")
    result = Translations::SourceDiff.call(from: long, to: long + " more")
    assert result.too_long?
    assert_empty result.segments
  end

  test "a 20,000-word body changed in one place answers quickly" do
    words = Array.new(20_000) { |i| "w#{i % 97}" }
    from = words.each_slice(200).map { |slice| slice.join(" ") }
    to = from.dup
    to[50] = to[50].sub("w3", "changed")
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Translations::SourceDiff.call(from: from, to: to)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    assert_operator elapsed, :<, 1.0
  end
end
