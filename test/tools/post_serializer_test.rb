require "test_helper"

class PostSerializerTest < ActiveSupport::TestCase
  test "serializes a post's translated and structural fields together" do
    post = Post.create!(content_type: :resume_entry, title: "Senior Engineer", excerpt: "Led the team",
      body: "<p>Details</p>", published_at: Time.current,
      metadata: { "company" => "Acme", "role_type" => "lead" })

    data = PostSerializer.call(post, :en)

    assert_equal post.id, data[:id]
    assert_equal "resume_entry", data[:content_type]
    assert_equal "en", data[:locale]
    assert_equal "Senior Engineer", data[:title]
    assert_equal post.slug, data[:slug]
    assert_equal "Led the team", data[:excerpt]
    # Not just assert_includes: mobility-actiontext's Post#body returns a
    # Mobility::Backends::ActionText::RichTextTranslation wrapper, and *that*
    # object's own #to_s renders through the full action_text/contents/_content
    # view+layout -- Rails' dev-mode "annotate rendered view files" template
    # comments and the trix-content div wrapper leak straight into the API
    # response. #body.body is the actual ActionText::Content inside it;
    # #to_html on that is the raw stored fragment with none of that.
    assert_equal "<p>Details</p>", data[:body]
    assert_equal true, data[:published]
    assert_equal post.published_at.iso8601, data[:published_at]
    assert_equal({ "company" => "Acme", "role_type" => "lead" }, data[:metadata])
  end

  test "published is false for a draft" do
    post = Post.create!(content_type: :blog, title: "Draft")

    data = PostSerializer.call(post, :en)

    assert_equal false, data[:published]
    assert_nil data[:published_at]
  end

  # The serializer trusts the caller to have already set the locale it's
  # asked to read in (Mobility.with_locale) -- it reads through the post's
  # plain attribute accessors rather than accepting an override, matching
  # every other locale-aware reader in this app (e.g. Page#slug_in).
  test "reads translated fields through whatever locale is currently active" do
    post = Post.create!(content_type: :blog, title: "English Title")
    Mobility.with_locale(:de) { post.update!(title: "Deutscher Titel") }

    data = Mobility.with_locale(:de) { PostSerializer.call(post, :de) }

    assert_equal "Deutscher Titel", data[:title]
  end
end
