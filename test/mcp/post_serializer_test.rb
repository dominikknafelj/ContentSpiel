require "test_helper"

class Mcp::PostSerializerTest < ActiveSupport::TestCase
  test "serializes a post's translated and structural fields together" do
    post = Post.create!(content_type: :resume_entry, title: "Senior Engineer", excerpt: "Led the team",
      body: "<p>Details</p>", published_at: Time.current,
      metadata: { "company" => "Acme", "role_type" => "lead" })

    data = Mcp::PostSerializer.call(post, :en)

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
    assert_equal "live", data[:status]
    assert_equal post.published_at.iso8601, data[:published_at]
    assert_equal({ "company" => "Acme", "role_type" => "lead" }, data[:fields])
    assert_not data.key?(:metadata)
    # Nothing lists this post, so it has no canonical URL (spec §5.3) -- the
    # serializer says so rather than guessing one from the post's own fields.
    assert_nil data[:url]
  end

  test "published is false and status is draft with no published_at" do
    post = Post.create!(content_type: :blog, title: "Draft")

    data = Mcp::PostSerializer.call(post, :en)

    assert_equal false, data[:published]
    assert_equal "draft", data[:status]
    assert_nil data[:published_at]
  end

  # `url` is the post's canonical permalink (spec §6.2), through the one
  # place a public URL is built -- `PublicSite::Urls` -- not assembled here
  # by hand from the page and slug.
  test "url is the canonical listing page's path plus the post's slug" do
    root = Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    blog = Page.create!(page_type: :standard, title: "Blog", slug: "blog", parent: root, published_at: Time.current)
    blog.content_blocks.create!(block_type: :post_list, position: 0)
    post = Post.create!(content_type: :blog, title: "Hello World", published_at: Time.current)

    data = Mcp::PostSerializer.call(post, :en)

    assert_equal "https://www.example.com/blog/hello-world", data[:url]
  end

  # A future published_at is `published: true` (kept for compatibility --
  # `published_at.present?` doesn't know about "yet") but `status: "scheduled"`,
  # not "live" -- the distinction this task adds `status` to make explicit.
  test "a scheduled post is published: true but status: scheduled" do
    post = Post.create!(content_type: :blog, title: "Future Post", published_at: 3.days.from_now)

    data = Mcp::PostSerializer.call(post, :en)

    assert_equal true, data[:published]
    assert_equal "scheduled", data[:status]
  end

  # The serializer trusts the caller to have already set the locale it's
  # asked to read in (Mobility.with_locale) -- it reads through the post's
  # plain attribute accessors rather than accepting an override, matching
  # every other locale-aware reader in this app (e.g. PublicSite::Paths#page_path).
  test "reads translated fields through whatever locale is currently active" do
    post = Post.create!(content_type: :blog, title: "English Title")
    Mobility.with_locale(:de) { post.update!(title: "Deutscher Titel") }

    data = Mobility.with_locale(:de) { Mcp::PostSerializer.call(post, :de) }

    assert_equal "Deutscher Titel", data[:title]
  end

  # A registered type's own `fields` -- not just a fixed list of built-ins --
  # decide what shows up here: `fields` merges the untranslated hash with
  # whichever locale's translations, and a translated field's value lives
  # under that locale specifically. A test-only type (open-types spec §8's
  # "open-type proof") is what exercises that path, since none of the
  # built-ins have a translated field.
  test "fields merges untranslated and this locale's translated values, for a type registered at runtime" do
    saved = ContentTypes.all.dup
    ContentTypes.reset!
    ContentTypes.register(:test_note) do |t|
      t.label "Test note"
      t.field :priority, :integer
      t.field :headline, :string, translated: true
    end

    post = Post.create!(content_type: :test_note, title: "A note", metadata: { "priority" => 3 })
    post.assign_fields({ headline: "Wichtig" }, locale: :de)
    post.save!

    data = Mcp::PostSerializer.call(post, :de)

    assert_equal({ "priority" => 3, "headline" => "Wichtig" }, data[:fields])
  ensure
    ContentTypes.reset!
    saved.each { |definition| ContentTypes.registry_put(definition) }
  end
end
