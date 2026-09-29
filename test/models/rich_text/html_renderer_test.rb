require "test_helper"

class RichText::HtmlRendererTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

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

  test "an image renders a figure with its alt and caption" do
    asset = create_media_asset
    html = render({ "type" => "image", "attrs" => { "asset_id" => asset.id, "alt" => "A", "caption" => "C" } })
    assert_includes html, "<figure"
    assert_includes html, %(alt="A")
    assert_includes html, %(src="#{asset.url}")
    assert_includes html, "<figcaption"
    assert_includes html, "C</figcaption>"
  end

  # Final fix wave (M6): an id stored as a String (an older import, a hand
  # edit) renders -- `Media::UsageIndex` already counts it as a usage, so
  # the page must show it too -- both through the document's preload and
  # through a context built without a document.
  test "an image whose asset_id is stored as a String still renders" do
    asset = create_media_asset
    html = render({ "type" => "image", "attrs" => { "asset_id" => asset.id.to_s, "alt" => "A" } })
    assert_includes html, %(src="#{asset.url}")

    context = RichText::RenderContext.new(locale: "en", urls: PublicSite::Urls.new)
    assert_equal asset, context.media_asset(asset.id.to_s)
    assert_nil context.media_asset("abc")
  end

  # Media library Task 5: an image node's alt/caption fall back to the
  # asset's own defaults (`Media::Asset#alt_text`/`#caption_text`) when the
  # node doesn't override them -- the same "override, then the asset's
  # default" chain `Blocks::ImageComponentTest` already covers for a block's
  # image.
  test "an image node with no alt/caption override falls back to the asset's own defaults" do
    asset = create_media_asset
    asset.update!(alt: "Library alt", caption: "Library caption")

    html = render({ "type" => "image", "attrs" => { "asset_id" => asset.id } })

    assert_includes html, %(alt="Library alt")
    assert_includes html, "Library caption</figcaption>"
  end

  # `RichText::RenderContext#media_asset` preloads every `image` node's
  # `Media::Asset` for the whole document in one query
  # (`Media::Asset.with_variants`), rather than `RichText::BuiltIns
  # .render_image` running `Media::Asset.find_by` once per node while the
  # tree is walked -- the number of `media_assets` queries a document costs
  # must not grow with how many image nodes it has.
  #
  # `Current.reset` between the two renders: `PublicSite.current_content_
  # version` (part of `#to_html`'s own cache key) memoizes onto `Current`,
  # which a real request only ever computes once -- resetting it here is
  # what keeps the *second* render in this test from getting that
  # memoized value's queries for free and understating its own count,
  # rather than the two renders being compared on equal footing the way
  # two separate requests would be.
  test "a document with many image nodes doesn't query media_assets once per node" do
    one_image = [ { "type" => "image", "attrs" => { "asset_id" => create_media_asset.id } } ]
    five_images = Array.new(5) { { "type" => "image", "attrs" => { "asset_id" => create_media_asset.id } } }

    Current.reset
    one_image_queries = count_media_asset_queries { render(*one_image) }

    Current.reset
    five_image_queries = count_media_asset_queries { render(*five_images) }

    assert_equal one_image_queries, five_image_queries,
      "adding more image nodes to one document shouldn't add media_assets queries (N+1). " \
      "1 image: #{one_image_queries} queries, 5 images: #{five_image_queries} queries"
  end

  def count_media_asset_queries
    count = 0
    callback = lambda { |*, payload| count += 1 if payload[:sql].include?("media_assets") }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    count
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

  # Final fix wave (C): the HTML also depends on code -- a renderer or
  # component markup change must not keep serving the old HTML out of Solid
  # Cache after a deploy. `RichText.code_revision` (the deploy's revision)
  # is part of the key.
  test "the render cache key varies by code revision" do
    original_cache, original_revision = Rails.cache, RichText.code_revision
    store = Class.new(ActiveSupport::Cache::MemoryStore) do
      def keys = (@keys ||= [])
      def fetch(name, *args, **options, &block) = (keys << name) && super
    end.new
    Rails.cache = store

    begin
      document = RichText::Document.new("type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ text("hi") ] } ])
      RichText.code_revision = "one"
      document.to_html(locale: "en", urls: PublicSite::Urls.new)
      RichText.code_revision = "two"
      document.to_html(locale: "en", urls: PublicSite::Urls.new)

      first, second = store.keys
      assert_includes first, "one"
      assert_includes second, "two"
      assert_equal first - [ "one" ], second - [ "two" ]
    ensure
      Rails.cache = original_cache
      RichText.code_revision = original_revision
    end
  end

  # Media library Task 5 fix round 1 (I1): a rendered body's `<img>` bakes
  # in which of its image's variants exist yet (`Media::PictureComponent`'s
  # `srcset`, built from `Media::Asset#srcset`'s own "only variants that
  # have actually finished processing" rule) -- and a `TransformJob`
  # finishing can change that well after the asset's own `updated_at` was
  # last touched, with no `Media::Asset` row changing at all. Without
  # `ActiveStorage::VariantRecord` maximum/count folded into `PublicSite
  # .content_version` (`app/models/public_site.rb`), a body rendered (and
  # cached, real cache store required -- same reasoning as every other
  # render-cache test here) before its image's variants finished would keep
  # serving `src`-only HTML forever, until some unrelated edit happened to
  # bump the version.
  #
  # `Current.reset` before each render: `content_version` memoizes on
  # `Current`, which a real request only ever computes once -- without
  # resetting it here, the second render would just reuse the first
  # render's memoized (now-stale) version and never see the variants that
  # finished in between, the same reasoning the N+1 test above needs it for.
  test "the render cache picks up an image's srcset once its variants finish processing" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    begin
      asset = create_media_asset(filename: "wide.png")
      asset.file.analyze
      metadata = asset.file.blob.metadata || {}
      asset.update_columns(width: metadata["width"], height: metadata["height"])

      document = RichText::Document.new("type" => "doc", "content" => [ { "type" => "image", "attrs" => { "asset_id" => asset.id } } ])

      Current.reset
      before_html = document.to_html(locale: "en", urls: PublicSite::Urls.new)
      assert_not_includes before_html, "srcset"

      perform_enqueued_jobs
      Current.reset

      after_html = document.to_html(locale: "en", urls: PublicSite::Urls.new)
      assert_includes after_html, "srcset"
    ensure
      Rails.cache = original_cache
    end
  end

  test "code_revision comes from KAMAL_VERSION, then a REVISION file, then a boot-time value" do
    assert_equal "abc123", RichText.resolve_code_revision(env: { "KAMAL_VERSION" => "abc123" }, revision_file: nil)

    Tempfile.create("REVISION") do |file|
      file.write("def456\n")
      file.flush
      assert_equal "def456", RichText.resolve_code_revision(env: {}, revision_file: Pathname(file.path))
    end

    assert_match(/\Aboot-\h{16}\z/, RichText.resolve_code_revision(env: {}, revision_file: Pathname("/nonexistent/REVISION")))
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
