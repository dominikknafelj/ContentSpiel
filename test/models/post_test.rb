require "test_helper"

class PostTest < ActiveSupport::TestCase
  test "title is required" do
    post = Post.new(content_type: :blog)
    assert_not post.valid?
    assert_includes post.errors[:title], "can't be blank"
  end

  # `title` presence means "this post is titled in some locale", not "titled in
  # the default locale" -- a post may legitimately exist in German before it is
  # written in English, and the reader falls back so nothing renders untitled.
  # Pinned explicitly because requiring the default locale here is a tempting
  # change that would make a post like this one invalid.
  test "a title in a non-default locale satisfies the presence requirement" do
    post = Mobility.with_locale(:de) do
      Post.new(content_type: :blog, title: "Hallo Welt", slug: "hallo-welt")
    end

    assert_nil post.title_en, "this post deliberately has no English title"
    assert Mobility.with_locale(:de) { post.valid? }, post.errors.full_messages.inspect
  end

  test "slug is auto-generated from title when blank" do
    post = Post.create!(content_type: :blog, title: "Hello World")
    assert_equal "hello-world", post.slug
  end

  # Task 8c / code-structure review finding #2: the same bug Page has -- a
  # post titled in only one locale used to leave every other locale's slug
  # blank, and `validates :slug, presence: true` reads through Mobility's
  # fallback, so the post still saved even without one. LocalizedSlug now
  # fills an untitled locale's slug from the site's default-locale title
  # instead of leaving it blank.
  test "slugs for untitled locales fall back to the site's default-locale title" do
    SiteSetting.instance.update!(default_locale: "de")

    post = Mobility.with_locale(:de) { Post.create!(content_type: :blog, title: "Hallo Welt") }

    assert_equal "hallo-welt", post.slug_en
    assert_equal "hallo-welt", post.slug_es
  end

  # When even the default locale has no title, the fallback walks
  # Mobility.available_locales and takes the first title it finds, rather
  # than leaving the slug blank.
  test "slugs fall back to the first present title when the default locale has none" do
    SiteSetting.instance.update!(default_locale: "de")

    post = Mobility.with_locale(:es) { Post.create!(content_type: :blog, title: "Hola Mundo") }

    assert_equal "hola-mundo", post.slug_en
    assert_equal "hola-mundo", post.slug_de
  end

  # The fallback only ever fills a *blank* slug -- an explicit one is left
  # alone even when the default-locale fallback would have produced something
  # different.
  test "an explicitly set slug is kept even when the default-locale fallback would differ" do
    SiteSetting.instance.update!(default_locale: "de")

    post = Mobility.with_locale(:de) do
      Post.create!(content_type: :blog, title: "Hallo Welt", slug_en: "hello-world")
    end

    assert_equal "hello-world", post.slug_en
  end

  # The fallback can produce a genuine collision, not just a hypothetical one:
  # two posts can each want the same borrowed slug in a locale neither of them
  # was actually titled in. `slug_is_unused_in_every_locale` (below) still
  # catches it -- reported against `slug_en`, the locale that actually
  # clashes, with a message that names it so an editor filling in a
  # default-locale-only post knows which tab to open.
  test "a fallback-filled slug can produce a real collision, reported against the locale it clashes in" do
    SiteSetting.instance.update!(default_locale: "de")
    Post.create!(content_type: :blog, title_en: "Team", slug_en: "team", title_de: "Mannschaft")

    clashing = Mobility.with_locale(:de) { Post.new(content_type: :blog, title: "Team") }

    # Ambient :de throughout: `clashing` is only titled in German, so title
    # presence (a separate, unrelated validation) would otherwise fail under
    # the default :en and mask the assertions this test actually cares about.
    Mobility.with_locale(:de) do
      assert_not clashing.valid?
      assert_includes clashing.errors[:slug_en], "has already been taken in EN"
      assert_empty clashing.errors[:slug_de], "the posts only clash in English, not German"

      clashing.slug_en = "team-2"
      assert clashing.valid?, clashing.errors.full_messages.inspect
    end
  end

  test "slug must be unique within the same content_type" do
    Post.create!(content_type: :blog, title: "Hello World")
    duplicate = Post.new(content_type: :blog, title: "Hello World")

    assert_not duplicate.valid?
    # Attributed to the locale that actually collides, so the admin form can
    # mark that locale's tab.
    assert_includes duplicate.errors[:slug_en], "has already been taken in EN"
  end

  test "the same slug is allowed across different content_types" do
    Post.create!(content_type: :blog, title: "Hello World")
    other = Post.new(content_type: :resume_entry, title: "Hello World")

    assert other.valid?
  end

  test "metadata defaults to an empty hash" do
    post = Post.create!(content_type: :blog, title: "Hello World")
    assert_equal({}, post.metadata)
  end

  test "body accepts rich text content" do
    post = Post.create!(content_type: :blog, title: "Hello World", body: "<p>Hi</p>")
    assert post.body.present?
    assert_includes post.body.to_plain_text, "Hi"
  end

  test "title, slug, and excerpt are independently translatable per locale" do
    post = Post.create!(content_type: :blog, title: "Hello World")

    Mobility.with_locale(:de) { post.update!(title: "Hallo Welt", slug: "hallo-welt") }
    Mobility.with_locale(:es) { post.update!(title: "Hola Mundo", slug: "hola-mundo") }

    assert_equal "Hello World", post.title
    assert_equal "hello-world", post.slug
    Mobility.with_locale(:de) do
      assert_equal "Hallo Welt", post.title
      assert_equal "hallo-welt", post.slug
    end
    Mobility.with_locale(:es) do
      assert_equal "Hola Mundo", post.title
      assert_equal "hola-mundo", post.slug
    end
  end

  # The assertions above would also pass against a per-instance cache that
  # never reached the database, so re-read the record from scratch.
  test "translations survive a round trip through the database" do
    post = Post.create!(content_type: :blog, title: "Hello World", excerpt: "A greeting")
    Mobility.with_locale(:de) { post.update!(title: "Hallo Welt", excerpt: "Ein Gruss") }

    reloaded = Post.find(post.id)

    assert_equal "Hello World", reloaded.title
    assert_equal "A greeting", reloaded.excerpt
    Mobility.with_locale(:de) do
      assert_equal "Hallo Welt", reloaded.title
      assert_equal "Ein Gruss", reloaded.excerpt
    end
  end

  # Proves the jsonb backend is what's storing these -- every locale lives in
  # one column on the posts row, not in a side table.
  test "translated plain-text attributes are stored in a jsonb column per attribute" do
    post = Post.create!(content_type: :blog, title: "Hello World")
    Mobility.with_locale(:de) { post.update!(title: "Hallo Welt") }

    raw = Post.connection.select_one("SELECT title FROM posts WHERE id = #{post.id}")

    assert_equal({ "en" => "Hello World", "de" => "Hallo Welt" }, JSON.parse(raw["title"]))
  end

  # Before this task, Mobility's own `fallbacks` plugin made every plain
  # reader fall back to a fixed :en. That's gone (config/initializers
  # /mobility.rb): the plain reader now returns the literal per-locale value,
  # and the fallback that public views need lives in `Locales.read` instead
  # (test/models/locales_test.rb covers it directly).
  test "the plain reader no longer falls back to the default locale" do
    post = Post.create!(content_type: :blog, title: "Hello World")

    assert_nil Mobility.with_locale(:de) { post.title }
    assert_equal "Hello World", Locales.read(post, :title, locale: "de")
  end

  test "slug uniqueness is scoped to content_type and locale, not shared across locales" do
    # A German title of its own, so "hello-world" isn't also this post's real
    # German slug (Task 8c's default-locale fallback would otherwise put it
    # there) -- the point here is the *other* post's German slug.
    Post.create!(content_type: :blog, title_en: "Hello World", slug_en: "hello-world", title_de: "Hallo Welt")

    Mobility.with_locale(:de) do
      other = Post.new(content_type: :blog, title: "Something Else", slug: "hello-world")
      assert other.valid?, "a slug used in one locale must not block the same slug in another locale"
    end
  end

  test "slug uniqueness still applies within a non-default locale" do
    Post.create!(content_type: :blog, title: "Hello World").tap do |post|
      Mobility.with_locale(:de) { post.update!(slug: "hallo-welt") }
    end

    Mobility.with_locale(:de) do
      duplicate = Post.new(content_type: :blog, title: "Etwas Anderes", slug: "hallo-welt")

      assert_not duplicate.valid?
      assert_includes duplicate.errors[:slug_de], "has already been taken in DE"
    end
  end

  # Without excluding the record itself, re-saving a post would report its own
  # slug as taken.
  test "a post does not collide with its own slug on update" do
    post = Post.create!(content_type: :blog, title: "Hello World")

    assert post.valid?
    Mobility.with_locale(:de) do
      post.slug = "hallo-welt"
      assert post.valid?
    end
  end

  test "body is independently translatable per locale" do
    post = Post.create!(content_type: :blog, title: "Hello World", body: "<p>Hi</p>")

    Mobility.with_locale(:de) { post.update!(body: "<p>Hallo</p>") }

    assert_includes post.body.to_plain_text, "Hi"
    Mobility.with_locale(:de) do
      assert_includes post.body.to_plain_text, "Hallo"
    end
  end

  test "translated rich text survives a round trip through the database" do
    post = Post.create!(content_type: :blog, title: "Hello World", body: "<p>Hi</p>")
    Mobility.with_locale(:de) { post.update!(body: "<p>Hallo</p>") }

    reloaded = Post.find(post.id)

    assert_includes reloaded.body.to_plain_text, "Hi"
    Mobility.with_locale(:de) do
      assert_includes reloaded.body.to_plain_text, "Hallo"
    end
    Mobility.with_locale(:es) do
      # No Spanish body was ever written, and plain readers no longer fall
      # back to another locale (see config/initializers/mobility.rb) --
      # that's `Locales.read`'s job now (see locales_test.rb), not the plain
      # reader's.
      assert_not reloaded.body.present?
    end
  end

  # The admin form submits every locale's slug in one request, under one
  # ambient locale. Validating only `Mobility.locale` lets the other locales'
  # slugs through to the database, where the per-locale unique indexes turn a
  # would-be form error into an unhandled RecordNotUnique.
  test "a slug duplicated in a locale other than the current one is rejected" do
    existing = Post.create!(content_type: :blog, title: "Hello World")
    Mobility.with_locale(:de) { existing.update!(slug: "hallo-welt") }

    duplicate = Post.new(content_type: :blog, title: "Something Else", slug: "something-else")
    duplicate.slug_de = "hallo-welt"

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:slug_de], "has already been taken in DE"
  end

  test "each locale's slug collision is reported against that locale's field" do
    existing = Post.create!(content_type: :blog, title: "Hello World")
    Mobility.with_locale(:es) { existing.update!(slug: "hola-mundo") }

    duplicate = Post.new(content_type: :blog, title: "Other", slug: "hello-world")
    duplicate.slug_es = "hola-mundo"

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:slug_en], "has already been taken in EN"
    assert_includes duplicate.errors[:slug_es], "has already been taken in ES"
    assert_empty duplicate.errors[:slug_de]
  end

  # Reading `slug` in a locale the post has no slug for returns the English one
  # via fallback. Validating that borrowed string as if it were the post's
  # real German slug would collide it with a German slug it does not actually
  # have -- which is exactly why the validation below reads the literal
  # per-locale accessor and skips a genuinely blank one, rather than reading
  # through Mobility's fallback.
  #
  # Task 8c means a *titled* post can no longer reach this validation with a
  # genuinely blank slug in any locale -- `LocalizedSlug` fills one from a
  # title the moment any title exists anywhere on the post. `update_columns`
  # forces the untitled, pre-fill state a row predating that feature (or a
  # bulk import) could still be in, the same way the "bypassed" tests further
  # down force other pre/post-validation states.
  test "a post with no slug anywhere is not blocked by another post's slug in the current locale" do
    untitled = Post.create!(content_type: :blog, title: "Placeholder")
    untitled.update_columns(title: {}, slug: {})
    german = Post.create!(content_type: :blog, title: "Etwas Anderes", slug: "etwas-anderes")
    Mobility.with_locale(:de) { german.update!(slug: "hello-world") }

    Mobility.with_locale(:de) do
      untitled.valid?
      assert_empty untitled.errors[:slug_de],
        "a post without a German slug of its own must not collide on another post's German slug"
    end
  end

  # The validation is the first line of defense; these indexes are the second,
  # and later models copy their shape, so pin it directly.
  test "the database rejects a same-locale duplicate slug when validation is bypassed" do
    Post.create!(content_type: :blog, title: "Hello World")
    sneaky = Post.create!(content_type: :blog, title: "Something Else")

    assert_raises ActiveRecord::RecordNotUnique do
      Post.transaction(requires_new: true) do
        sneaky.update_column(:slug, { "en" => "hello-world" })
      end
    end
  end

  test "the database allows the same slug in two different locales" do
    # A German title of its own, so "hello-world" isn't also this post's real
    # German slug (Task 8c's default-locale fallback would otherwise put it
    # there) -- the point here is the *other* post's German slug.
    Post.create!(content_type: :blog, title_en: "Hello World", slug_en: "hello-world", title_de: "Hallo Welt")
    other = Post.create!(content_type: :blog, title: "Something Else")

    other.update_column(:slug, { "en" => "something-else", "de" => "hello-world" })

    assert_equal "hello-world", Mobility.with_locale(:de) { Post.find(other.id).slug }
  end

  test "the database allows the same slug under a different content_type" do
    Post.create!(content_type: :blog, title: "Hello World")
    other = Post.create!(content_type: :resume_entry, title: "Something Else")

    other.update_column(:slug, { "en" => "hello-world" })

    assert_equal "hello-world", Post.find(other.id).slug
  end

  test "the translated locales are the site's configured locales" do
    assert_equal %i[en de es], Mobility.available_locales
  end
end
