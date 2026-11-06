require "test_helper"

class Posts::DetailComponentTest < ActiveSupport::TestCase
  include ComponentTestHelper

  test "shows date, excerpt and tags" do
    post = Post.create!(content_type: :blog, title: "Hello", excerpt: "Short summary",
      published_at: Time.zone.local(2026, 9, 12), body: rich_doc("Body text"))
    post.tags << Tag.create!(name: "hotwire")

    render_inline(Posts::DetailComponent.new(post: post))

    assert_text "12 Sep 2026"
    assert_text "Short summary"
    assert_text "hotwire"
    assert_selector "article .cs-prose", text: "Body text"
  end

  # The tags are one sentence, not a list (plan ruling 3): a mono label, then the
  # names exactly as stored, joined by commas, in the small sans. No transform on
  # the names, no links.
  test "a post's tags are one line: a mono Tagged label, then the names as stored, joined by commas, in the small sans" do
    post = Post.create!(content_type: :blog, title: "Tagged", published_at: Time.zone.local(2026, 9, 12),
      body: rich_doc("Body text"))
    post.tags << Tag.create!(name: "rails")
    post.tags << Tag.create!(name: "iOS")

    render_inline(Posts::DetailComponent.new(post: post))

    assert_selector "p.post-tags"
    assert_equal "Tagged rails, iOS", page.find("p.post-tags").text.squish
    assert_selector "p.post-tags span.font-cs-mono", text: "Tagged", exact_text: true
    assert_selector "p.post-tags span.font-cs.text-small.text-meta", text: "rails, iOS", exact_text: true
    assert_no_selector "p.post-tags .uppercase.font-cs"
    assert_no_selector "p.post-tags", text: "RAILS"
    assert_no_selector "ul"
    assert_no_selector "p.post-tags a"
  end

  test "a tag that looks like markup is text" do
    post = Post.create!(content_type: :blog, title: "Markup", published_at: Time.zone.local(2026, 9, 12),
      body: rich_doc("Body text"))
    post.tags << Tag.create!(name: "<b>x</b>")

    render_inline(Posts::DetailComponent.new(post: post))

    assert_no_selector "p.post-tags b"
    assert_includes page.find("p.post-tags").text, "<b>x</b>"
  end

  test "a post without tags draws nothing of them" do
    post = Post.create!(content_type: :blog, title: "Bare", published_at: Time.zone.local(2026, 9, 12),
      body: rich_doc("Body text"))

    render_inline(Posts::DetailComponent.new(post: post))

    assert_no_selector "p.post-tags"
    assert_no_text "Tagged"
  end
end
