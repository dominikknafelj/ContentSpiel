require "test_helper"

class SlugGenerationTest < ActiveSupport::TestCase
  setup do
    @root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
  end

  test "a new page gets a slug per locale from that locale's title" do
    page = Page.create!(parent: @root, page_type: :standard, title_en: "About Us", title_de: "Über uns")

    assert_equal "about-us", page.slug_en
    assert_equal "uber-uns", page.slug_de

    # Spanish has no title of its own, so it falls back to the site's
    # default-locale (English) title rather than staying blank -- a blank
    # non-root slug collapses onto the parent's path (Task 8c / see page.rb's
    # comment on the two-pages-one-URL bug that produces).
    assert_equal "about-us", page.slug_es
  end

  test "an existing slug is never overwritten when the title changes" do
    page = Page.create!(parent: @root, page_type: :standard, title_en: "About", slug_en: "who-we-are")
    page.update!(title_en: "About the team")

    assert_equal "who-we-are", page.reload.slug_en
  end

  # Before Task 8c, German had no slug at all until a German title arrived,
  # so this proved a later translation still got one. Now German is filled
  # from the English title the moment the page is created -- "never
  # overwrite" (above) applies to that fallback-derived slug exactly as it
  # does to a hand-typed one, so a real German title arriving afterwards must
  # not retroactively replace it.
  test "a fallback-filled slug is not retroactively replaced once a real translation arrives" do
    page = Page.create!(parent: @root, page_type: :standard, title_en: "About")
    assert_equal "about", page.slug_de, "German has no title yet, so it falls back to the English one"

    page.update!(title_de: "Über")

    assert_equal "about", page.reload.slug_de
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
