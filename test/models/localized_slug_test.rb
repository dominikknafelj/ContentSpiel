require "test_helper"

class LocalizedSlugTest < ActiveSupport::TestCase
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

  # The fallback title (`Locales.fallback_chain`, via `Current.site`) reads
  # `SiteSetting.instance`, a database row -- not worth fetching on every save
  # of a page that has no blank slug to fill in the first place. Counting
  # queries, rather than stubbing (no mocking library, per project
  # constraints), so this exercises the real callback.
  test "saving a page with every locale already slugged does not query SiteSetting" do
    page = Page.create!(parent: @root, page_type: :standard, title_en: "About", slug_en: "about",
      title_de: "Über uns", slug_de: "uber-uns", title_es: "Sobre Nosotros", slug_es: "sobre-nosotros")

    site_setting_queries = 0
    ActiveSupport::Notifications.subscribed(lambda { |_name, _started, _finished, _unique_id, payload|
      site_setting_queries += 1 if payload[:sql]&.include?("site_settings")
    }, "sql.active_record") do
      page.update!(title_en: "About the team")
    end

    assert_equal 0, site_setting_queries,
      "no locale's slug was blank, so the default-locale fallback should never be looked up"
  end

  test "saving a post with every locale already slugged does not query SiteSetting" do
    post = Post.create!(content_type: :blog, title_en: "Hello World", slug_en: "hello-world",
      title_de: "Hallo Welt", slug_de: "hallo-welt", title_es: "Hola Mundo", slug_es: "hola-mundo")

    site_setting_queries = 0
    ActiveSupport::Notifications.subscribed(lambda { |_name, _started, _finished, _unique_id, payload|
      site_setting_queries += 1 if payload[:sql]&.include?("site_settings")
    }, "sql.active_record") do
      post.update!(title_en: "Hello There")
    end

    assert_equal 0, site_setting_queries,
      "no locale's slug was blank, so the default-locale fallback should never be looked up"
  end

  test "slug uniqueness is enforced per scope and locale through the macro" do
    a = Post.create!(content_type: :blog, title: "Same")
    b = Post.new(content_type: :blog, title: "Same")
    assert_not b.valid?
    assert b.errors[Mobility.normalize_locale_accessor(:slug, :en)].any? { |m| m.include?("EN") }
    assert Post.new(content_type: :now_update, title: "Same").valid?
  end

  # Task 11 fix round 1: `String#parameterize` transliterates through ASCII,
  # so a title with no Latin letters at all -- Japanese, here, one of the
  # ~37 supported languages (spec §4.1) -- comes out "". `slugify`'s fallback
  # keeps the title's own letters/digits instead of dropping them, so the
  # locale still gets a real, working URL rather than silently having none.
  test "a title with no Latin letters gets a Unicode slug instead of a blank one" do
    with_locales(%w[en ja], default: "en") do
      about = Page.create!(page_type: :standard, parent: @root, title_ja: "日本語のタイトル")

      assert_equal "日本語のタイトル", about.slug_ja
      assert_equal "/日本語のタイトル", about.full_path("ja")
    end
  end

  # "Über uns" has Latin letters with diacritics -- `parameterize` handles
  # those fine via transliteration -- so the Unicode-preserving fallback
  # never runs here. Pinned so a future change to `slugify` can't quietly
  # make this cross-locale test-writing-adjacent case go through the wrong
  # branch and still pass.
  test "a title with Latin diacritics still slugifies through parameterize, not the fallback" do
    page = Page.create!(parent: @root, page_type: :standard, title_de: "Über uns")

    assert_equal "uber-uns", page.slug_de
  end

  # `slugify`'s fallback strips a title down to nothing when it has no
  # letters or digits in *any* script -- bare punctuation, here -- the same
  # outcome as a blank title, and `fill_blank_slugs` leaves the slug blank
  # rather than writing "". `LocalizedSlug#slug_present_in_every_enabled_
  # locale` is what catches that: presence is checked per enabled locale, not
  # "some locale has one," because a slug (unlike a title) has no fallback
  # when read back.
  test "a title made only of punctuation leaves that locale's slug blank, caught by the presence check" do
    page = Page.new(page_type: :standard, parent: @root, title_en: "About", title_de: "…")

    assert_not page.valid?
    assert_equal "about", page.slug_en
    assert_nil page.slug_de
    assert_includes page.errors[:slug_de], "can't be blank in DE"
  end

  # Trash spec §2 "URLs: freed at once": a page rebuilt in a trashed one's
  # place must be able to take its slug. Trashed through `update!` rather
  # than `update_columns`, so its `public_paths` rows go too (see
  # `PublicSite::Paths.compute_path`) -- otherwise `HasPublicPaths` would
  # refuse the new page's `/about` as another record's live address, which
  # is a different check from the one under test here.
  test "a trashed page doesn't hold its slug" do
    gone = Page.create!(parent: @root, page_type: :standard, title_en: "About")
    gone.update!(trashed_at: Time.current)

    fresh = Page.create!(parent: @root, page_type: :standard, title_en: "About")

    assert_equal "about", fresh.slug_en
    assert gone.slug_taken?(:en, "about"), "the kept page now holds it"
    assert_not fresh.slug_taken?(:en, "about"), "the trashed page no longer counts"
  end

  test "a trashed post doesn't hold its slug" do
    gone = Post.create!(content_type: :blog, title_en: "Hello")
    gone.update!(trashed_at: Time.current)

    fresh = Post.create!(content_type: :blog, title_en: "Hello")

    assert_equal "hello", fresh.slug_en
    assert_not fresh.slug_taken?(:en, "hello")
  end

  # A trashed record never needs a unique slug while it's in the trash --
  # `Trash::Restore` finds it a free one on the way out -- so a save of the
  # trashed record itself (its own trashing, or anything else) is never
  # refused over a slug a kept record has since taken.
  test "a trashed page's own save skips the uniqueness check" do
    gone = Page.create!(parent: @root, page_type: :standard, title_en: "About")
    gone.update!(trashed_at: Time.current)
    Page.create!(parent: @root, page_type: :standard, title_en: "About")

    assert gone.reload.valid?, gone.errors.full_messages.to_sentence
  end
end
