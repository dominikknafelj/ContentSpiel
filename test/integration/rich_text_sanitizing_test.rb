require "test_helper"

# Task 8b (structure review #37), carried over to JSON documents (design
# spec §3.3/§9's "scrubber/CSP regression"): a rich-text body is no longer
# authored HTML, but its *inputs* still are untrusted -- MCP's Markdown can
# carry raw HTML, and a jsonb row can be hand-edited into any shape. The
# guarantees are layered: `RichText::Markdown` drops raw HTML, the model
# rejects documents that don't validate, `RichText::HtmlRenderer` only ever
# emits tag-helper-escaped markup for registered types, and its output still
# passes through `RichTextScrubber`. These tests render through the real
# public pipeline (PagesController#show), not the pieces in isolation, so a
# regression in any one layer's wiring fails here.
class RichTextSanitizingTest < ActionDispatch::IntegrationTest
  setup do
    SiteSetting.instance.update!(tagline: "Writing about Rails")
    @root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
  end

  test "raw iframe HTML in Markdown never reaches a page's rich text" do
    document, = RichText::Document.from_markdown(%(Before\n\n<iframe src="https://evil.example/x"></iframe>\n\nAfter))
    @root.content_blocks.create!(block_type: :rich_text, position: 0, body_doc: document.to_h)
    get "/"

    assert_response :success
    assert_not_includes response.body, "evil.example"
    assert_not_includes response.body, "<iframe"
    assert_includes response.body, "Before"
    assert_includes response.body, "After"
  end

  test "raw iframe HTML in Markdown never reaches a post's rich text" do
    blog = Page.create!(parent: @root, page_type: :standard, title: "Blog", published_at: Time.current)
    blog.content_blocks.create!(block_type: :post_list, position: 0)
    document, = RichText::Document.from_markdown(%(Before <iframe src="https://evil.example/x"></iframe> after))
    Post.create!(content_type: :blog, title: "Hello", published_at: Time.current, body_doc: document.to_h)
    get "/blog/hello"

    assert_response :success
    assert_not_includes response.body, "<iframe"
  end

  # A hand-edited row can hold anything (`update_column` skips validation):
  # an unregistered node type with iframe-shaped attrs renders only its
  # children's text, never markup built from those attrs.
  test "an unknown node type smuggled into a stored document renders no iframe" do
    block = @root.content_blocks.create!(block_type: :rich_text, position: 0)
    block.update_column(:body_doc, { "en" => { "type" => "doc", "content" => [
      { "type" => "iframe", "attrs" => { "src" => "https://evil.example/x", "srcdoc" => "<script>alert(1)</script>" },
        "content" => [ { "type" => "text", "text" => "Visible" } ] } ] } })
    get "/"

    assert_response :success
    assert_not_includes response.body, "<iframe"
    assert_not_includes response.body, "evil.example"
    assert_not_includes response.body, "alert(1)"
    assert_includes response.body, "Visible"
  end

  test "a youtube node renders the youtube-nocookie embed iframe" do
    @root.content_blocks.create!(block_type: :rich_text, position: 0, body_doc: rich_doc(%(Intro\n\n::youtube{id="dQw4w9WgXcQ"})))
    get "/"

    assert_response :success
    assert_select "iframe[src='https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ']"
  end

  test "ordinary rich text formatting survives" do
    @root.content_blocks.create!(block_type: :rich_text, position: 0,
      body_doc: rich_doc("**Bold** and [a link](https://example.com)\n\n- one\n- two"))
    get "/"

    assert_response :success
    assert_select ".content-block--rich-text strong", text: "Bold"
    assert_select ".content-block--rich-text a[href='https://example.com']", text: "a link"
    assert_select ".content-block--rich-text ul li", count: 2
  end

  test "the public page response carries a narrow Content-Security-Policy header" do
    get "/"

    assert_response :success
    csp = response.headers["Content-Security-Policy"]
    assert csp.present?, "expected a Content-Security-Policy header"
    assert_includes csp, "frame-src 'self' https://www.youtube-nocookie.com"
  end
end
