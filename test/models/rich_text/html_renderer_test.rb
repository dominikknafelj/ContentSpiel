require "test_helper"

class RichText::HtmlRendererTest < ActiveSupport::TestCase
  def render(*content, preview: false)
    RichText::Document.new("type" => "doc", "content" => content).to_html(locale: "en", urls: PublicSite::Urls.new(preview: preview))
  end
  def text(value, *marks) = { "type" => "text", "text" => value, "marks" => marks }.compact

  test "standard nodes and marks" do
    html = render(
      { "type" => "heading", "attrs" => { "level" => 3 }, "content" => [ text("Title") ] },
      { "type" => "paragraph", "content" => [ text("a", { "type" => "bold" }), text("b", { "type" => "italic" }), { "type" => "hardBreak" }, text("c", { "type" => "code" }) ] },
      { "type" => "bulletList", "content" => [ { "type" => "listItem", "content" => [ { "type" => "paragraph", "content" => [ text("one") ] } ] } ] },
      { "type" => "blockquote", "content" => [ { "type" => "paragraph", "content" => [ text("q") ] } ] },
      { "type" => "codeBlock", "content" => [ text("x < y") ] },
      { "type" => "horizontalRule" })
    assert_includes html, "<h3>Title</h3>"
    assert_includes html, "<strong>a</strong><em>b</em><br><code>c</code>"
    assert_includes html, "<ul><li><p>one</p></li></ul>"
    assert_includes html, "<pre><code>x &lt; y</code></pre>"
    assert_includes html, "<hr>"
  end

  test "hostile documents render inert" do
    html = render(
      { "type" => "paragraph", "content" => [ text("<script>alert(1)</script>"),
        text("x", { "type" => "link", "attrs" => { "href" => "javascript:alert(1)" } }) ] },
      { "type" => "youtube", "attrs" => { "id" => "\"><iframe src=evil" } })
    assert_not_includes html, "<script>"
    assert_not_includes html, "javascript:"
    assert_not_includes html, "evil"
  end

  test "internal links resolve through public URLs, including preview" do
    page = create_page(title: "About")
    link = { "type" => "internalLink", "attrs" => { "type" => "page", "id" => page.id } }
    assert_includes render({ "type" => "paragraph", "content" => [ text("go", link) ] }), %(href="/about")
    assert_includes render({ "type" => "paragraph", "content" => [ text("go", link) ] }, preview: true), %(href="/preview/about")
  end

  test "missing asset and missing link target render gracefully" do
    link = { "type" => "internalLink", "attrs" => { "type" => "page", "id" => 0 } }
    html = render({ "type" => "paragraph", "content" => [ text("gone", link) ] }, { "type" => "image", "attrs" => { "asset_id" => 0 } })
    assert_includes html, "gone"
    assert_not_includes html, "<a"
    assert_not_includes html, "<img"
  end

  test "youtube renders the nocookie embed" do
    assert_includes render({ "type" => "youtube", "attrs" => { "id" => "dQw4w9WgXcQ" } }), "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ"
  end

  test "unknown node types keep their text" do
    assert_includes render({ "type" => "marquee", "content" => [ text("kept") ] }), "kept"
  end

  test "unknown mark types keep their text unmarked" do
    html = render({ "type" => "paragraph", "content" => [ text("plain", { "type" => "sparkle" }) ] })
    assert_includes html, "<p>plain</p>"
  end

  # Fix round 1 (I2): a page/post that exists but isn't publicly visible --
  # unpublished, here -- renders exactly like a missing target outside
  # preview, but keeps its link in preview, where editors need to see and
  # click it. `PublicSite::Resolver.visible?` is the shared rule; see
  # `RichText::BuiltIns.render_internal_link`'s comment for why this
  # reuses it instead of re-deriving "published, with published ancestors".
  test "internal links to a non-visible target render as text publicly but link in preview" do
    page = create_page(title: "Draft Page", published: false)
    link = { "type" => "internalLink", "attrs" => { "type" => "page", "id" => page.id } }

    public_html = render({ "type" => "paragraph", "content" => [ text("go", link) ] })
    assert_includes public_html, "go"
    assert_not_includes public_html, "<a"

    preview_html = render({ "type" => "paragraph", "content" => [ text("go", link) ] }, preview: true)
    assert_includes preview_html, %(href="/preview/draft-page")
  end

  # Fix round 1 (m3): `safe_href?` decodes HTML/numeric-character-reference
  # entities and strips control characters before checking the scheme, so
  # an encoded `javascript:` can't sneak past a check that only ever looked
  # at the literal (still-encoded) String.
  test "encoded and control-character javascript schemes are rejected" do
    encoded = render({ "type" => "paragraph", "content" => [ text("x", { "type" => "link", "attrs" => { "href" => "javascript&#58;alert(1)" } }) ] })
    assert_not_includes encoded, "<a"
    assert_not_includes encoded, "javascript:"

    hex_entity = render({ "type" => "paragraph", "content" => [ text("x", { "type" => "link", "attrs" => { "href" => "&#x6A;avascript:alert(1)" } }) ] })
    assert_not_includes hex_entity, "<a"
    assert_not_includes hex_entity, "javascript:"
  end

  # Fix round 1 (m5): same document, three renders differing only in
  # locale/preview -- with a real cache store (the test suite otherwise
  # runs on :null_store, which would never expose a cache key collision)
  # the render cache key has to fold in both, or the second and third
  # renders here would wrongly return the first render's cached HTML.
  test "the render cache key varies by locale and by preview" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    begin
      page = create_page(title: "Cache Target", translations: { "de" => { title: "Cache Target" } })
      link = { "type" => "internalLink", "attrs" => { "type" => "page", "id" => page.id } }
      document = RichText::Document.new("type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ text("go", link) ] } ])

      html_en_public = document.to_html(locale: "en", urls: PublicSite::Urls.new)
      html_en_preview = document.to_html(locale: "en", urls: PublicSite::Urls.new(preview: true))
      html_de_public = document.to_html(locale: "de", urls: PublicSite::Urls.new)

      assert_includes html_en_public, %(href="/cache-target")
      assert_includes html_en_preview, %(href="/preview/cache-target")
      assert_includes html_de_public, %(href="/de/cache-target")
      assert_not_equal html_en_public, html_en_preview
      assert_not_equal html_en_public, html_de_public
    ensure
      Rails.cache = original_cache
    end
  end

  # Fix round 1 (I1): a document that never passed `RichText::Document
  # #validate` can hand the renderer any JSON shape at all -- these are
  # exactly the malformed shapes `RichText::DocumentTest` proves `#validate`
  # itself survives. `#to_html` must be equally total: every case below
  # only needs to return a String, never raise.
  test "malformed structure renders inert instead of raising" do
    urls = PublicSite::Urls.new

    content_as_hash = RichText::Document.new("type" => "doc", "content" => { "type" => "paragraph" })
    assert_kind_of String, content_as_hash.to_html(locale: "en", urls: urls)

    nil_in_content = RichText::Document.new("type" => "doc", "content" => [ nil, { "type" => "paragraph", "content" => [ text("ok") ] } ])
    assert_includes nil_in_content.to_html(locale: "en", urls: urls), "ok"

    bare_array_node = RichText::Document.new("type" => "doc", "content" => [ [ 1, 2 ] ])
    assert_kind_of String, bare_array_node.to_html(locale: "en", urls: urls)

    marks_as_hash = { "type" => "text", "text" => "x", "marks" => { "type" => "bold" } }
    marks_hash_doc = RichText::Document.new("type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ marks_as_hash ] } ])
    assert_includes marks_hash_doc.to_html(locale: "en", urls: urls), "x"

    bad_attrs = { "type" => "heading", "attrs" => [ "not", "a", "hash" ], "content" => [ text("x") ] }
    attrs_doc = RichText::Document.new("type" => "doc", "content" => [ bad_attrs ])
    assert_kind_of String, attrs_doc.to_html(locale: "en", urls: urls)
  end

  # Fix round 1 (addendum): `#to_html` computes `#digest` (part of the cache
  # key) *before* `RichText::HtmlRenderer` ever runs, so a pathologically
  # deep document has to survive both `RichText::Document#digest` and the
  # renderer's own recursion guard -- 5000 nested `blockquote`s is well past
  # `RichText::Document::MAX_DEPTH` (50, `RichText::HtmlRenderer`'s own
  # ceiling) and what `RichText::DocumentTest`'s own 500-deep regression
  # test uses, to prove this isn't merely "deep enough to dodge the exact
  # number that test happens to check." `#digest` itself has no depth
  # ceiling at all as of fix round 2 (`RichText::Document#write_canonical`
  # is iterative, not recursive, precisely so it never needs one) -- this
  # test is really only exercising `RichText::HtmlRenderer`'s guard at this
  # point; the digest-side regression net lives in the test below.
  test "a pathologically deep document renders without a SystemStackError" do
    node = { "type" => "text", "text" => "x" }
    5000.times { node = { "type" => "blockquote", "content" => [ node ] } }

    html = RichText::Document.new("type" => "doc", "content" => [ node ]).to_html(locale: "en", urls: PublicSite::Urls.new)
    assert_kind_of String, html
  end

  # Fix round 2: re-review of the round-1 addendum found a Critical --
  # `RichText::Document#canonicalize` capped recursion at `MAX_DEPTH` and
  # replaced everything past it with a fixed placeholder, which sounds
  # safe but silently collapsed every leaf value past ~25 nesting levels
  # (each tree level cost 2 depth units: Hash -> "content" Array -> child
  # Hash) to that *same* placeholder -- so two documents differing only in
  # a leaf 24 levels deep collided on `#digest`, and since the render
  # cache (`RichText::Document#to_html`) is keyed on that digest, one
  # document's cached HTML got served back for the other's. A real cache
  # store, not the suite's default `:null_store`, is what actually
  # exercises that failure mode (`:null_store` never serves a stale cache
  # hit, so it would never catch this) -- same reasoning as the "render
  # cache key" test above. `RichText::Document#digest` now streams a
  # canonical, depth-unbounded serialization straight into a running
  # `Digest::SHA256` (`#write_canonical`) instead of capping/truncating
  # anything, so two documents can never collide regardless of depth.
  #
  # 24 levels deep is exactly the old collision point; 60 is comfortably
  # past it, to prove this isn't merely "past the exact number the old bug
  # happened to hit." 60 is *also* past `RichText::HtmlRenderer`'s own,
  # separate `MAX_DEPTH` (50, one unit per tree level there, not two) --
  # a legitimate, unrelated guard (fix round 1's I1) that intentionally
  # drops content beyond it, so `to_html` for both 60-deep documents
  # renders identically (both empty past that point) with no leaf text in
  # either. That's the renderer's own guard doing its job, not a digest
  # collision -- the two are distinguished at every depth, this test just
  # only checks *rendered content* differs where the renderer doesn't
  # itself discard that content (comfortably within its cap, at 24).
  test "documents differing only at a deep leaf never collide, at any depth" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    begin
      [ 24, 60 ].each do |depth|
        node_a = { "type" => "text", "text" => "AAAA" }
        depth.times { node_a = { "type" => "blockquote", "content" => [ node_a ] } }
        node_b = { "type" => "text", "text" => "BBBB" }
        depth.times { node_b = { "type" => "blockquote", "content" => [ node_b ] } }

        doc_a = RichText::Document.new("type" => "doc", "content" => [ node_a ])
        doc_b = RichText::Document.new("type" => "doc", "content" => [ node_b ])
        assert_not_equal doc_a.digest, doc_b.digest, "digests collided at depth #{depth}"

        html_a = doc_a.to_html(locale: "en", urls: PublicSite::Urls.new)
        html_b = doc_b.to_html(locale: "en", urls: PublicSite::Urls.new)
        assert_kind_of String, html_a
        assert_kind_of String, html_b

        next if depth > RichText::Document::MAX_DEPTH # past HtmlRenderer's own, separate content-dropping cap

        assert_includes html_a, "AAAA"
        assert_includes html_b, "BBBB"
        assert_not_equal html_a, html_b, "to_html output collided at depth #{depth}"
      end
    ensure
      Rails.cache = original_cache
    end
  end

  test "a very deep document still digests without raising" do
    node = { "type" => "text", "text" => "x" }
    5000.times { node = { "type" => "blockquote", "content" => [ node ] } }

    assert_kind_of String, RichText::Document.new("type" => "doc", "content" => [ node ]).digest
  end
end
