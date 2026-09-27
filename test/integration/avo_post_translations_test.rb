require "test_helper"

# Covers the admin side of Mobility: the Post form has to offer one tab per
# locale, and a submission has to land in the right locale rather than
# overwriting whatever locale the admin happened to be browsing in.
#
# Avo 4.2.3 has no Mobility integration of its own, so the locale switcher is
# assembled in app/avo/resources/post.rb out of Avo's tabs plus Mobility's
# locale accessors. That makes it worth testing against the real rendered form
# rather than trusting the field declarations to line up.
class AvoPostTranslationsTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "translator@example.com", password: "password123")
    sign_in_as(@user)

    @post = Post.create!(content_type: :blog, title: "Hello World", body: "<p>Hi</p>")
    Mobility.with_locale(:de) { @post.update!(title: "Hallo Welt", body: "<p>Hallo</p>") }
  end

  test "the post form renders one tab per enabled locale" do
    get "/avo/resources/posts/#{@post.id}/edit"

    assert_response :success

    Locales.enabled.each do |locale|
      # Avo renders each tab as a `tabs__item` link plus a panel div carrying
      # `data-tab-id`; the tab titles are the locale codes, upper-cased.
      assert_match(/data-tabs-tab-name-param="#{locale.to_s.upcase}"/, response.body,
        "expected a tab switcher entry for #{locale}")
      assert_match(/data-tabs-target="tabPanel" data-tab-id="#{locale.to_s.upcase}"/, response.body,
        "expected a tab panel for #{locale}")
    end
  end

  test "the post form exposes a separate input per locale for every translated field" do
    get "/avo/resources/posts/#{@post.id}/edit"

    assert_response :success

    Locales.enabled.each do |locale|
      %w[title slug excerpt body].each do |attribute|
        assert_includes response.body, %(name="post[#{attribute}_#{locale}]"),
          "expected an input for #{attribute} in #{locale}"
      end
    end
  end

  # The whole point of the per-locale accessors: an untranslated locale's tab
  # must come up empty, not pre-filled with the English text (which an editor
  # would then unknowingly save as the Spanish translation).
  test "an untranslated locale's inputs render empty rather than falling back" do
    get "/avo/resources/posts/#{@post.id}/edit"

    assert_response :success

    # Read each input tag whole: Avo renders `value=` before `name=`, so a
    # regex anchored on the name and looking rightwards would never see it.
    assert_match(/\bvalue="Hello World"/, title_input_for(:en))
    assert_match(/\bvalue="Hallo Welt"/, title_input_for(:de))
    assert_no_match(/\bvalue=/, title_input_for(:es),
      "the Spanish title input must not be pre-filled from the English translation")
  end

  test "submitting the form writes each locale independently" do
    put "/avo/resources/posts/#{@post.id}", params: { post: {
      content_type: "blog",
      title_en: "Hello World", slug_en: "hello-world", excerpt_en: "A greeting",
      title_de: "Hallo Welt", slug_de: "hallo-welt", excerpt_de: "Ein Gruss",
      title_es: "Hola Mundo", slug_es: "hola-mundo", excerpt_es: "Un saludo",
      body_en: "<p>Hi</p>", body_de: "<p>Hallo</p>", body_es: "<p>Hola</p>"
    } }

    assert_response :redirect

    saved = Post.find(@post.id)

    {
      en: [ "Hello World", "hello-world", "A greeting", "Hi" ],
      de: [ "Hallo Welt", "hallo-welt", "Ein Gruss", "Hallo" ],
      es: [ "Hola Mundo", "hola-mundo", "Un saludo", "Hola" ]
    }.each do |locale, (title, slug, excerpt, body)|
      Mobility.with_locale(locale) do
        assert_equal title, saved.title, "wrong title in #{locale}"
        assert_equal slug, saved.slug, "wrong slug in #{locale}"
        assert_equal excerpt, saved.excerpt, "wrong excerpt in #{locale}"
        assert_equal body, saved.body.to_plain_text.strip, "wrong body in #{locale}"
      end
    end
  end

  # A slug that is already taken in one locale must not be reported as taken
  # when the admin is filling in a different locale's tab.
  test "the form accepts a slug that is only taken in another locale" do
    Post.create!(content_type: :blog, title: "Unrelated", slug: "shared-slug")

    put "/avo/resources/posts/#{@post.id}", params: { post: {
      content_type: "blog", slug_de: "shared-slug"
    } }

    assert_response :redirect
    assert_equal "shared-slug", Mobility.with_locale(:de) { Post.find(@post.id).slug }
  end

  # The form writes all three locales at once while the request itself runs
  # under :en. A German slug that is already taken has to come back as a form
  # error -- if only the current locale is validated it sails through to the
  # per-locale unique index and 500s instead.
  test "a slug already taken in a non-current locale comes back as a form error" do
    taken = Post.create!(content_type: :blog, title: "Unrelated", slug: "unrelated")
    Mobility.with_locale(:de) { taken.update!(slug: "belegt") }

    put "/avo/resources/posts/#{@post.id}", params: { post: {
      content_type: "blog", slug_en: "hello-world", slug_de: "belegt"
    } }

    assert_response :unprocessable_entity

    # Without a per-locale validation the collision is caught by the database
    # instead, and Avo renders Postgres' own message into the page.
    assert_no_match(/duplicate key value violates unique constraint/, response.body,
      "a taken slug must surface as a validation error, not a raw Postgres error")
    assert_includes response.body, "has already been taken"

    # `slug_de` reads the literal German value; plain `slug` would fall back to
    # the English one and pass no matter what. It's "hello-world", not nil or
    # "hallo-welt": the setup block's `Post.create!` (English title only, at
    # that point) already gave every untitled locale -- German included -- a
    # slug from that English title (Task 8c's default-locale fallback), and
    # `LocalizedSlug` never overwrites an existing slug, so the setup
    # block's later `update!(title: "Hallo Welt", ...)` left it alone. The
    # point here is that the rejected submission didn't overwrite it with
    # "belegt" either.
    assert_equal "hello-world", Post.find(@post.id).slug_de,
      "the duplicate German slug must not have been written"
  end

  private
    def title_input_for(locale)
      response.body[/<input[^>]*name="post\[title_#{locale}\]"[^>]*>/].tap do |input|
        assert input, "expected a title input for #{locale}"
      end
    end
end
