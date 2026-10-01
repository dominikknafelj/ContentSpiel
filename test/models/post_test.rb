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

  test "body stores a JSON document per locale" do
    post = Post.create!(content_type: :blog, title: "Hello World", body: rich_doc("Hi"))

    document = post.reload.body_document(locale: Locales.default)
    assert_kind_of RichText::Document, document
    assert_equal rich_doc("Hi"), document.to_h
  end

  test "body_document is an empty document for a locale never written" do
    post = Post.create!(content_type: :blog, title: "Hello World")

    assert post.body_document(locale: "de").blank?
  end

  test "assign_body writes only the given locale" do
    post = Post.create!(content_type: :blog, title: "Hello World", body: rich_doc("Hi"))

    post.assign_body(rich_doc("Hallo"), locale: "de")
    post.save!
    post.reload

    assert_equal rich_doc("Hi"), post.body_document(locale: "en").to_h
    assert_equal rich_doc("Hallo"), post.body_document(locale: "de").to_h
  end

  test "assign_body accepts a RichText::Document and a JSON string" do
    post = Post.create!(content_type: :blog, title: "Hello World")

    post.assign_body(RichText::Document.new(rich_doc("Doc")), locale: "en")
    post.assign_body(rich_doc("Json").to_json, locale: "de")
    post.save!
    post.reload

    assert_equal rich_doc("Doc"), post.body_document(locale: "en").to_h
    assert_equal rich_doc("Json"), post.body_document(locale: "de").to_h
  end

  test "an invalid body document is a validation error on body and is never saved" do
    post = Post.create!(content_type: :blog, title: "Hello World", body: rich_doc("Kept"))

    post.assign_body({ "type" => "doc", "content" => [ { "type" => "heading", "attrs" => { "level" => 1 },
      "content" => [ { "type" => "text", "text" => "H1" } ] } ] }, locale: "de")

    assert_not post.save
    assert post.errors[:body].any? { |message| message.include?("heading.level") }, post.errors.full_messages.inspect
    assert_equal rich_doc("Kept"), post.reload.body_document(locale: "en").to_h
    assert post.body_document(locale: "de").blank?
  end

  test "malformed JSON for a body is a validation error, not an exception" do
    post = Post.create!(content_type: :blog, title: "Hello World")

    post.assign_body("{not json", locale: "en")

    assert_not post.valid?
    assert post.errors[:body].any?
  end

  # Fix round 1 (m3): nothing at all is not "clear this locale" -- it
  # used to delete the locale's document silently.
  test "a body that is nil, blank or JSON null is rejected, and the stored document kept" do
    [ nil, "", "  ", "null" ].each_with_index do |value, index|
      post = Post.create!(content_type: :blog, title: "Hello #{index}", body: rich_doc("Kept"))

      post.assign_body(value, locale: "en")

      assert_not post.save, "#{value.inspect} should not save"
      assert post.errors[:body].any?
      assert_equal rich_doc("Kept"), post.reload.body_document(locale: "en").to_h
    end
  end

  test "an explicit empty document clears a body" do
    post = Post.create!(content_type: :blog, title: "Hello", body: rich_doc("Gone"))

    post.assign_body(RichText::Document::EMPTY_HASH.to_json, locale: "en")
    post.save!

    assert post.reload.body_document(locale: "en").blank?
  end

  test "a valid assignment after a rejected one clears the rejection" do
    post = Post.create!(content_type: :blog, title: "Hello")

    post.assign_body("null", locale: "en")
    post.assign_body(rich_doc("Fine"), locale: "en")

    assert post.save, post.errors.full_messages.inspect
  end

  # A stale reference in a document nobody touched in this save (an
  # internal link whose target was later deleted) must not block unrelated
  # edits: only the locales whose document actually changed are validated.
  test "an unchanged body document is not re-validated" do
    target = create_post(title: "Target")
    link = { "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [
      { "type" => "text", "text" => "see", "marks" => [ { "type" => "internalLink", "attrs" => { "type" => "post", "id" => target.id } } ] } ] } ] }
    post = Post.create!(content_type: :blog, title: "Hello World", body: link)
    target.destroy!

    post.reload.title = "Renamed"
    assert post.save, post.errors.full_messages.inspect
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

  test "translated rich text survives a round trip through the database" do
    post = Post.create!(content_type: :blog, title: "Hello World", body: rich_doc("Hi"))
    Mobility.with_locale(:de) { post.update!(body: rich_doc("Hallo")) }

    reloaded = Post.find(post.id)

    assert_equal rich_doc("Hi"), reloaded.body_document(locale: "en").to_h
    assert_equal rich_doc("Hallo"), reloaded.body_document(locale: "de").to_h
    # No Spanish body was ever written, and `body_document` reads the
    # literal locale -- falling back is `Locales.read`'s job (see
    # locales_test.rb), not the model reader's.
    assert reloaded.body_document(locale: "es").blank?
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
      assert_not_includes untitled.errors[:slug_de], "has already been taken in DE",
        "a post without a German slug of its own must not collide on another post's German slug"
      # Still fails *presence* for de (and every other enabled locale) --
      # genuinely blank, not a false collision -- covered by
      # `LocalizedSlugTest` directly.
      assert_includes untitled.errors[:slug_de], "can't be blank in DE"
    end
  end

  # Foundations task 4 (spec §5.2) drops the per-language unique slug indexes
  # on posts outright: a post's literal slug is no longer required to be
  # unique at the database layer, only by `LocalizedSlug`'s own validation
  # above -- neither post here has a listing page, so neither has a public
  # path to clash on either (spec §5.3's "a post without a listing page has
  # no path to clash on"). The database-level safety net this test used to
  # pin now lives one level up, on the *address* two records would actually
  # collide at: see `HasPublicPaths#public_paths_are_available` and
  # `PublicSite::PathsTest#"a post cannot take a path a child page already
  # holds"`.
  test "bypassing the slug validation no longer collides at the database layer" do
    Post.create!(content_type: :blog, title: "Hello World")
    sneaky = Post.create!(content_type: :blog, title: "Something Else")

    assert_nothing_raised do
      sneaky.update_column(:slug, { "en" => "hello-world" })
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

  # Mobility's available locales are every *supported* language (spec §4.1),
  # not the site's own enabled subset -- that's `Locales.enabled`, a runtime
  # setting Mobility can't see. Widening this list needs no migration and no
  # per-locale accessor to be added by hand.
  test "the translated locales are every supported language" do
    assert_equal ::SUPPORTED_LOCALES.keys.map(&:to_sym), Mobility.available_locales
  end

  # `fields_are_valid` checks a required translated field against
  # `Locales.default`'s own document, not the *ambient* `I18n.locale` --
  # whatever a request happened to leave it at, unrelated to the site's own
  # default -- which would otherwise reject a post that saved correctly the
  # moment that ambient locale doesn't match the site's default.
  test "fields_are_valid checks a required translated field at the site's default locale, not the ambient one" do
    with_locales(%w[de en], default: "de")

    saved = ContentTypes.all.dup
    begin
      ContentTypes.register("test/headline") { |t| t.label "Headline"; t.field :headline, :string, required: true, translated: true }

      post = Post.new(content_type: "test/headline", title: "Hi")
      post.assign_fields({ "headline" => "Hallo" }, locale: "de")

      assert post.valid?, post.errors.full_messages.to_sentence
    ensure
      ContentTypes.reset!
      saved.each { |definition| ContentTypes.registry_put(definition) }
    end
  end

  # Task 7 fix round 1 (I2): the editor resends the whole document on every
  # edit, dead references included -- a body linking to a since-deleted
  # page (or showing a since-deleted image) must still save after an edit,
  # while a *new* link to a missing record is still rejected.
  test "a body with a dead reference can still be edited; a new dead reference can't be added" do
    target = create_page(title: "Doomed")
    asset = create_media_asset
    post = create_post(title: "Notes")
    linked = ->(text, id) { { "type" => "text", "text" => text, "marks" => [ { "type" => "internalLink", "attrs" => { "type" => "page", "id" => id } } ] } }
    image = { "type" => "image", "attrs" => { "asset_id" => asset.id, "alt" => "", "caption" => "" } }
    body = ->(*paragraph) { { "type" => "doc", "content" => [ { "type" => "paragraph", "content" => paragraph }, image ] } }

    post.assign_body(body.call(linked.call("go", target.id)), locale: :en)
    assert post.save, post.errors.full_messages.to_sentence

    delete_for_good(target)
    asset.destroy!

    post.reload.assign_body(body.call({ "type" => "text", "text" => "Edited " }, linked.call("go", target.id)), locale: :en)
    assert post.save, post.errors.full_messages.to_sentence

    post.assign_body(body.call(linked.call("go", target.id), linked.call("new", 999_999)), locale: :en)
    assert_not post.save
    assert_includes post.errors[:body].join, "internalLink.id is invalid"
  end

  # The stored document's marks are in the schema's canonical order,
  # whatever order the editor sent them in.
  test "assign_body stores marks in canonical order" do
    post = create_post(title: "Notes")
    post.assign_body({ "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [
      { "type" => "text", "text" => "x", "marks" => [ { "type" => "link", "attrs" => { "href" => "/a" } }, { "type" => "bold" } ] } ] } ] }.to_json, locale: :en)

    assert_equal %w[bold link], post.body(locale: :en).dig("content", 0, "content", 0, "marks").map { |mark| mark["type"] }
  end

  test "a legacy body that only differs by normalisation doesn't block an unrelated save" do
    post = create_post(title: "Legacy")
    # Stored before the content-model rules: bold with edge whitespace (which
    # #normalized hoists) next to a code+bold run the schema now forbids.
    legacy = { "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [
      { "type" => "text", "text" => "a " },
      { "type" => "text", "text" => " b ", "marks" => [ { "type" => "bold" } ] },
      { "type" => "text", "text" => "c", "marks" => [ { "type" => "bold" }, { "type" => "code" } ] } ] } ] }
    post.update_column(:body, { "en" => legacy })
    post.reload

    post.title = "Retitled"
    post.assign_body(legacy.to_json, locale: "en")

    assert post.save, post.errors.full_messages.to_sentence
  end
end
