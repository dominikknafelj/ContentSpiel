require "test_helper"

class SlugGenerationTest < ActiveSupport::TestCase
  setup do
    @root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
  end

  test "a new page gets a slug per locale from that locale's title" do
    page = Page.create!(parent: @root, page_type: :standard, title_en: "About Us", title_de: "Über uns")

    assert_equal "about-us", page.slug_en
    assert_equal "uber-uns", page.slug_de
    assert_nil page.slug_es
  end

  test "an existing slug is never overwritten when the title changes" do
    page = Page.create!(parent: @root, page_type: :standard, title_en: "About", slug_en: "who-we-are")
    page.update!(title_en: "About the team")

    assert_equal "who-we-are", page.reload.slug_en
  end

  test "a translation added later gets its slug on update" do
    page = Page.create!(parent: @root, page_type: :standard, title_en: "About")
    page.update!(title_de: "Über")

    assert_equal "uber", page.reload.slug_de
  end

  # Mobility's `presence` plugin (config/initializers/mobility.rb) turns a
  # blank string written to a translated attribute into nil, so the root's
  # slug reads back as nil rather than "" -- either way, `generates_slugs?`
  # (parent_id nil) means this concern never touches it.
  test "the root page keeps its empty slug" do
    assert_nil @root.reload.slug_en
  end

  test "a post gets a slug per locale too" do
    post = Post.create!(content_type: :blog, title_en: "Hello World", title_de: "Hallo Welt")

    assert_equal "hello-world", post.slug_en
    assert_equal "hallo-welt", post.slug_de
  end
end
