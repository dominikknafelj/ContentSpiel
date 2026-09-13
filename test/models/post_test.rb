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

  test "slug must be unique within the same content_type" do
    Post.create!(content_type: :blog, title: "Hello World")
    duplicate = Post.new(content_type: :blog, title: "Hello World")

    assert_not duplicate.valid?
    # Attributed to the locale that actually collides, so the admin form can
    # mark that locale's tab.
    assert_includes duplicate.errors[:slug_en], "has already been taken"
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

  test "falls back to the default locale when a translation is missing" do
    post = Post.create!(content_type: :blog, title: "Hello World")

    Mobility.with_locale(:de) do
      assert_equal "Hello World", post.title
    end
  end

  test "slug uniqueness is scoped to content_type and locale, not shared across locales" do
    Post.create!(content_type: :blog, title: "Hello World")

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
      assert_includes duplicate.errors[:slug_de], "has already been taken"
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
      # No Spanish body was ever written, so this is the English fallback.
      assert_includes reloaded.body.to_plain_text, "Hi"
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
    assert_includes duplicate.errors[:slug_de], "has already been taken"
  end

  test "each locale's slug collision is reported against that locale's field" do
    existing = Post.create!(content_type: :blog, title: "Hello World")
    Mobility.with_locale(:es) { existing.update!(slug: "hola-mundo") }

    duplicate = Post.new(content_type: :blog, title: "Other", slug: "hello-world")
    duplicate.slug_es = "hola-mundo"

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:slug_en], "has already been taken"
    assert_includes duplicate.errors[:slug_es], "has already been taken"
    assert_empty duplicate.errors[:slug_de]
  end

  # Reading `slug` in a locale the post has no slug for returns the English one
  # via fallback. Validating *that* string as if it were the German slug makes
  # a post collide with a German slug it does not actually have.
  test "a post with no slug in the current locale is not blocked by another post's slug there" do
    english_only = Post.create!(content_type: :blog, title: "Hello World")
    german = Post.create!(content_type: :blog, title: "Etwas Anderes", slug: "etwas-anderes")
    Mobility.with_locale(:de) { german.update!(slug: "hello-world") }

    Mobility.with_locale(:de) do
      assert english_only.valid?,
        "a post without a German slug must not collide on another post's German slug"
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
    Post.create!(content_type: :blog, title: "Hello World")
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
