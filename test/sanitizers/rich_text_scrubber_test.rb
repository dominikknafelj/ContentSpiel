require "test_helper"

# `RichTextScrubber` directly (Task 5 fix round 1, m1): since rich text is
# rendered from JSON documents, no public path can hand the scrubber raw
# iframe HTML any more (`rich_text_sanitizing_test.rb`), so the scrubber's
# own rules are pinned here instead -- it's still the last line of defence
# behind `RichText::HtmlRenderer` (and a plugin's `html` renderer).
class RichTextScrubberTest < ActiveSupport::TestCase
  def scrub(html) = Rails::HTML5::SafeListSanitizer.new.sanitize(html, scrubber: RichTextScrubber.new)

  test "an iframe pointed at an arbitrary host is stripped" do
    html = scrub(%(<p>Before</p><iframe src="https://evil.example/x"></iframe><p>After</p>))

    assert_not_includes html, "<iframe"
    assert_not_includes html, "evil.example"
    assert_includes html, "<p>Before</p>"
  end

  test "a srcdoc iframe without an src is stripped" do
    html = scrub(%(<iframe srcdoc="<script>alert(1)</script>"></iframe>))

    assert_not_includes html, "<iframe"
    assert_not_includes html, "srcdoc"
    assert_not_includes html, "alert(1)"
  end

  test "a srcdoc iframe is stripped even when its src is the allowed youtube-nocookie embed" do
    html = scrub(%(<iframe src="https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ" srcdoc="<script>alert(1)</script>"></iframe>))

    assert_not_includes html, "<iframe"
    assert_not_includes html, "srcdoc"
  end

  test "a plain youtube-nocookie embed iframe survives" do
    html = scrub(%(<iframe src="https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ" allowfullscreen></iframe>))

    assert_includes html, %(<iframe src="https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ")
  end

  test "on* event handler attributes are stripped" do
    html = scrub(%(<p onclick="x()">Hi</p><img src="/a.png" onerror="y()">))

    assert_not_includes html, "onclick"
    assert_not_includes html, "onerror"
    assert_includes html, "Hi"
  end

  test "script tags are removed" do
    assert_not_includes scrub(%(<p>ok</p><script>alert(1)</script>)), "<script"
  end
end
