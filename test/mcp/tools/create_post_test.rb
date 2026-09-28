require "test_helper"

class Mcp::Tools::CreatePostTest < ActiveSupport::TestCase
  def call_tool(**arguments)
    delivered = JSON.parse(JSON.generate(arguments), symbolize_names: true)
    Mcp::Tools::CreatePost.call(**delivered, server_context: { user: @user })
  end

  setup do
    @user = User.create!(email_address: "agent@example.com", password: "password123")
  end

  test "creates a post and returns it" do
    response = nil

    assert_difference "Post.count", 1 do
      response = call_tool(content_type: "blog", title: "New Post", body: "Hello **world**")
    end

    data = JSON.parse(response.content.first[:text])
    post = Post.find(data["id"])
    assert_equal "blog", post.content_type
    assert_equal "New Post", post.title
    assert_equal rich_doc("Hello **world**"), post.body_document(locale: "en").to_h
    assert_equal "Hello **world**\n", data["body"]
    assert_equal 1, response.content.size, "no warnings, no extra content"
  end

  test "body Markdown with directives and cs: links becomes the matching nodes" do
    target = create_post(title: "Target")
    asset = create_media_asset

    response = call_tool(content_type: "blog", title: "Rich", locale: "de",
      body: "See [it](cs:post/#{target.id})\n\n::youtube{id=\"dQw4w9WgXcQ\"}\n\n::image{asset=\"#{asset.id}\" alt=\"A\" caption=\"C\"}")

    post = Post.find(JSON.parse(response.content.first[:text])["id"])
    types = post.body_document(locale: "de").to_h["content"].map { |node| node["type"] }
    assert_equal %w[paragraph youtube image], types
    mark = post.body_document(locale: "de").to_h.dig("content", 0, "content", 1, "marks", 0)
    assert_equal({ "type" => "internalLink", "attrs" => { "type" => "post", "id" => target.id } }, mark)
  end

  test "conversion warnings are appended to the response text, and the post is still saved" do
    response = nil
    assert_difference "Post.count", 1 do
      response = call_tool(content_type: "blog", title: "Warned", body: "Text\n\n::nope{x=\"1\"}")
    end

    assert_not response.error?
    warnings = response.content.last[:text]
    assert_match(/warning/i, warnings)
    assert_match(/nope/, warnings)
  end

  test "a draft (no published: true) has no published_at" do
    response = call_tool(content_type: "blog", title: "Draft Post")

    data = JSON.parse(response.content.first[:text])
    assert_equal false, data["published"]
  end

  test "published: true sets published_at" do
    response = call_tool(content_type: "blog", title: "Live Post", published: true)

    data = JSON.parse(response.content.first[:text])
    assert_equal true, data["published"]
  end

  test "writes the translated fields in the given locale" do
    response = call_tool(content_type: :blog, title: "Deutscher Titel", locale: "de")

    data = JSON.parse(response.content.first[:text])
    post = Post.find(data["id"])
    assert_equal "Deutscher Titel", Mobility.with_locale(:de) { post.title }
    assert_nil Mobility.with_locale(:en) { post.title }
  end

  test "writes in the site's default locale when none is given" do
    SiteSetting.instance.update!(default_locale: "de")

    response = call_tool(content_type: :blog, title: "Deutscher Titel")

    data = JSON.parse(response.content.first[:text])
    post = Post.find(data["id"])
    assert_equal "Deutscher Titel", Mobility.with_locale(:de) { post.title }
  end

  test "a locale outside the site's enabled languages returns an error response" do
    response = nil

    assert_no_difference "Post.count" do
      response = call_tool(content_type: "blog", title: "Bonjour", locale: "fr")
    end

    assert response.error?
  end

  test "returns an error response, not a crash, for an invalid content_type" do
    response = nil

    assert_no_difference "Post.count" do
      response = call_tool(content_type: "not_a_real_type", title: "Whatever")
    end

    assert response.error?
  end

  test "fields creates a post with its content type's typed fields" do
    response = call_tool(content_type: "resume_entry", title: "Staff Engineer",
      fields: { company: "Acme", role_type: "lead", start_date: "2023-01-01" })

    data = JSON.parse(response.content.first[:text])
    assert_equal({ "company" => "Acme", "role_type" => "lead", "start_date" => "2023-01-01" }, data["fields"])
    assert_not data.key?("metadata")
  end

  test "an invalid field value returns an MCP error response naming the field" do
    response = nil

    assert_no_difference "Post.count" do
      response = call_tool(content_type: "resume_entry", title: "Staff Engineer", fields: { role_type: "boss" })
    end

    assert response.error?
    assert_match(/role type/i, response.content.first[:text])
  end

  test "the body is documented as Markdown with directives and cs: links" do
    description = Mcp::Tools::CreatePost.input_schema_value.to_h.dig(:properties, :body, :description)

    assert_includes description, "Markdown"
    assert_includes description, '::youtube{id="'
    assert_includes description, '::image{asset="'
    assert_includes description, "cs:page/"
    assert_includes description, "cs:post/"
  end
end
