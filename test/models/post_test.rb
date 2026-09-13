require "test_helper"

class PostTest < ActiveSupport::TestCase
  test "title is required" do
    post = Post.new(content_type: :blog)
    assert_not post.valid?
    assert_includes post.errors[:title], "can't be blank"
  end

  test "slug is auto-generated from title when blank" do
    post = Post.create!(content_type: :blog, title: "Hello World")
    assert_equal "hello-world", post.slug
  end

  test "slug must be unique within the same content_type" do
    Post.create!(content_type: :blog, title: "Hello World")
    duplicate = Post.new(content_type: :blog, title: "Hello World")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:slug], "has already been taken"
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
      assert_includes duplicate.errors[:slug], "has already been taken"
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

  test "the translated locales are the site's configured locales" do
    assert_equal %i[en de es], Mobility.available_locales
  end
end
