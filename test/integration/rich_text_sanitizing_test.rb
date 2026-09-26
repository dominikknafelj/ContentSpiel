require "test_helper"

# Task 8b (structure review #37): a rich text body is authored HTML -- MCP's
# `body` param takes it raw, and the editor's paste fallback isn't guaranteed
# to route every iframe through YoutubeEmbed -- so ActionText::ContentHelper's
# scrubber (RichTextScrubber, app/sanitizers/rich_text_scrubber.rb) is the
# only thing standing between a rich text body and an arbitrary iframe
# reaching the public page. These tests render through the real public
# pipeline (PagesController#show), not just the scrubber in isolation, so a
# regression in the initializer wiring (config/initializers/action_text.rb)
# would fail here even if the scrubber class itself were correct.
class RichTextSanitizingTest < ActionDispatch::IntegrationTest
  setup do
    SiteSetting.instance.update!(tagline: "Writing about Rails")
    @root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
  end

  test "an iframe pointed at an arbitrary host is stripped from a page's rich text" do
    @root.content_blocks.create!(block_type: :rich_text, position: 0,
      body: '<p>Before</p><iframe src="https://evil.example/x"></iframe><p>After</p>')
    get "/"

    assert_response :success
    assert_not_includes response.body, "evil.example"
    assert_not_includes response.body, "<iframe"
    assert_includes response.body, "Before"
    assert_includes response.body, "After"
  end

  test "an iframe pointed at an arbitrary host is stripped from a post's rich text" do
    blog = Page.create!(parent: @root, page_type: :standard, title: "Blog", published_at: Time.current)
    blog.content_blocks.create!(block_type: :post_list, position: 0)
    Post.create!(content_type: :blog, title: "Hello", published_at: Time.current,
      body: '<p>Before</p><iframe src="https://evil.example/x"></iframe><p>After</p>')
    get "/blog/hello"

    assert_response :success
    assert_not_includes response.body, "evil.example"
    assert_not_includes response.body, "<iframe"
  end

  test "a srcdoc iframe is stripped even without an src" do
    @root.content_blocks.create!(block_type: :rich_text, position: 0,
      body: '<p>Before</p><iframe srcdoc="<script>alert(1)</script>"></iframe><p>After</p>')
    get "/"

    assert_response :success
    assert_not_includes response.body, "<iframe"
    assert_not_includes response.body, "srcdoc"
    assert_not_includes response.body, "alert(1)"
  end

  test "a srcdoc iframe is stripped even when its src is the allowed youtube-nocookie embed" do
    @root.content_blocks.create!(block_type: :rich_text, position: 0,
      body: '<iframe src="https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ" srcdoc="<script>alert(1)</script>"></iframe>')
    get "/"

    assert_response :success
    assert_not_includes response.body, "<iframe"
    assert_not_includes response.body, "srcdoc"
  end

  test "a youtube-nocookie embed iframe survives" do
    embed = YoutubeEmbed.create!(video_id: "dQw4w9WgXcQ")
    body = %(<p>Intro</p><action-text-attachment sgid="#{embed.attachable_sgid}"></action-text-attachment>)
    @root.content_blocks.create!(block_type: :rich_text, position: 0, body: body)
    get "/"

    assert_response :success
    assert_select "iframe[src='https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ']"
  end

  test "ordinary rich text formatting survives" do
    @root.content_blocks.create!(block_type: :rich_text, position: 0,
      body: '<p><strong>Bold</strong> and <a href="https://example.com">a link</a></p><ul><li>one</li><li>two</li></ul>')
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
