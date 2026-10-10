require "test_helper"

class Notes::TextTest < ActiveSupport::TestCase
  def parts(body) = Notes::Text.parts(body).map { |part| [ part.kind, part.value ] }

  test "plain text is one part" do
    assert_equal [ [ :text, "Just words <b>not markup</b>" ] ], parts("Just words <b>not markup</b>")
    assert_equal [], parts("")
  end

  test "a mention and a link are parts of their own" do
    assert_equal [ [ :text, "Ask " ], [ :mention, 12 ], [ :text, " about " ], [ :link, "https://example.com/a?b=1" ], [ :text, "." ] ],
      parts("Ask @[12] about https://example.com/a?b=1.")
  end

  test "punctuation after a link stays text, and a link can end the body" do
    assert_equal [ [ :text, "(see " ], [ :link, "http://example.com/x" ], [ :text, ")" ] ], parts("(see http://example.com/x)")
    assert_equal [ [ :link, "https://example.com" ] ], parts("https://example.com")
  end

  test "only http and https become links" do
    assert_equal [ [ :text, "javascript:alert(1) and ftp://x.test" ] ], parts("javascript:alert(1) and ftp://x.test")
  end
end
