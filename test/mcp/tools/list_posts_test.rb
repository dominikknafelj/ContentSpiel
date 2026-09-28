require "test_helper"

# Tool arguments are called the way a transport actually delivers them --
# JSON round-tripped first so nested hashes arrive with symbol keys, not the
# string keys a Ruby literal would use directly (see the mcp gem's own
# "Tool argument keys" docs: a tool that only passes tests with string-keyed
# args can still fail against a real client).
class Mcp::Tools::ListPostsTest < ActiveSupport::TestCase
  def call_tool(**arguments)
    delivered = JSON.parse(JSON.generate(arguments), symbolize_names: true)
    Mcp::Tools::ListPosts.call(**delivered, server_context: { user: @user })
  end

  setup do
    @user = User.create!(email_address: "agent@example.com", password: "password123")
  end

  test "lists every post when given no filter" do
    Post.create!(content_type: :blog, title: "A Blog Post")
    Post.create!(content_type: :resume_entry, title: "A Resume Entry")

    response = call_tool

    titles = JSON.parse(response.content.first[:text]).map { |post| post["title"] }
    assert_equal [ "A Blog Post", "A Resume Entry" ].sort, titles.sort
  end

  test "filters by content_type" do
    Post.create!(content_type: :blog, title: "A Blog Post")
    Post.create!(content_type: :resume_entry, title: "A Resume Entry")

    response = call_tool(content_type: "blog")

    titles = JSON.parse(response.content.first[:text]).map { |post| post["title"] }
    assert_equal [ "A Blog Post" ], titles
  end

  test "reads titles in the given locale" do
    post = Post.create!(content_type: :blog, title: "English Title")
    Mobility.with_locale(:de) { post.update!(title: "Deutscher Titel") }

    response = call_tool(locale: "de")

    titles = JSON.parse(response.content.first[:text]).map { |post| post["title"] }
    assert_equal [ "Deutscher Titel" ], titles
  end

  test "defaults to the site's default locale when none is given" do
    SiteSetting.instance.update!(default_locale: "de")
    post = Post.create!(content_type: :blog, title: "English Title")
    Mobility.with_locale(:de) { post.update!(title: "Deutscher Titel") }

    response = call_tool

    titles = JSON.parse(response.content.first[:text]).map { |post| post["title"] }
    assert_equal [ "Deutscher Titel" ], titles
  end

  test "a locale outside the site's enabled languages returns an error response" do
    response = call_tool(locale: "fr")

    assert response.error?
  end

  # List responses are a summary, not the full record -- a body-per-post
  # dump would bloat every listing for content an agent has to ask for by
  # id anyway (Mcp::Tools::GetPost).
  test "list entries omit the full body" do
    Post.create!(content_type: :blog, title: "A Blog Post", body_doc: rich_doc("Full content"))

    response = call_tool

    assert_not_includes response.content.first[:text], "Full content"
  end
end
