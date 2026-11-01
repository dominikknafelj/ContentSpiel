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

  # `s` is one more tag on the list and nothing else: attributes are one
  # list for every tag, so it keeps what any element keeps (`class`) and
  # loses what any element loses (a handler, an unknown attribute).
  test "a struck text keeps its element, with the attributes any element may keep and no other" do
    html = scrub(%(<p>was <s class="x" onclick="alert(1)" data-x="1" style="color:red">struck</s></p>))

    assert_equal %(<p>was <s class="x">struck</s></p>), html
    assert_equal scrub(%(<p>was <em class="x" onclick="alert(1)" data-x="1" style="color:red">struck</em></p>)).gsub("em>", "s>").gsub("<em", "<s"), html
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

  # Media library Task 5: `Media::PictureComponent`'s own `<img>` carries
  # four attributes the built-in Rails safe-list never had reason to allow
  # (`src`/`width`/`height`/`alt` were already there) -- all four must
  # survive the scrub, or every responsive image on the site would render
  # `src` alone the instant it went through `RichText::HtmlRenderer`.
  test "an img's srcset, sizes, loading and decoding attributes survive the scrub" do
    html = scrub(%(<img src="/a.webp" srcset="/a-480.webp 480w, /a-960.webp 960w" sizes="100vw" width="480" height="320" loading="lazy" decoding="async" alt="x">))

    assert_includes html, %(srcset="/a-480.webp 480w, /a-960.webp 960w")
    assert_includes html, %(sizes="100vw")
    assert_includes html, %(width="480")
    assert_includes html, %(height="320")
    assert_includes html, %(loading="lazy")
    assert_includes html, %(decoding="async")
  end

  test "a rendered rich-text image keeps its preview style, its preview src and its state attributes" do
    style = Media::PictureComponent.preview_style("data:image/webp;base64,UklGRg==")
    html = scrub(%(<img src="data:image/webp;base64,UklGRg==" style='#{style}' data-image-preview data-image-empty width="3" height="2" alt="x">))

    assert_includes html, %(src="data:image/webp;base64,UklGRg==")
    assert_includes html, "background:url"
    assert_includes html, "data-image-preview"
    assert_includes html, "data-image-empty"
  end

  test "any other style on an img, another data: src, and the state attributes on another element are dropped" do
    html = scrub(%(<img src="/a.webp" style="position:fixed;inset:0" alt="x"><p style="background:url(&quot;data:image/webp;base64,AAAA&quot;) center/cover no-repeat" data-image-preview data-image-empty>t</p><img src="data:text/html;base64,AAAA" alt="y">))

    assert_not_includes html, "style="
    assert_not_includes html, "data-image-preview"
    assert_not_includes html, "data-image-empty"
    assert_not_includes html, "data:text/html"
  end

  test "an img keeps a data: src only when it is exactly the WebP preview, however the scheme is written" do
    [ "data:image/png;base64,iVBORw0KGgo=", "da\nta:image/png;base64,iVBORw0KGgo=", "da\tta:image/png;base64,iVBORw0KGgo=",
      "&#1;data:image/png;base64,iVBORw0KGgo=", "&#x20;DATA:image/png;base64,iVBORw0KGgo=",
      "data:image/webp,notbase64", " data:image/webp;base64,UklGRg==", "data:image/webp;base64,UklGRg==\n" ].each do |src|
      html = scrub(%(<img src="#{src}" alt="x">))
      assert_not_includes html.downcase.delete("\n\t "), "data:image", "kept #{src.inspect}: #{html}"
    end
    assert_includes scrub(%(<img src="data:image/webp;base64,UklGRg==" alt="x">)), "data:image/webp;base64,UklGRg=="
  end
end
