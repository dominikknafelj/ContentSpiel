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
      response = call_tool(content_type: "blog", title: "New Post", body: "<p>Hello</p>")
    end

    data = JSON.parse(response.content.first[:text])
    post = Post.find(data["id"])
    assert_equal "blog", post.content_type
    assert_equal "New Post", post.title
    assert_includes post.body.to_s, "Hello"
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
end
