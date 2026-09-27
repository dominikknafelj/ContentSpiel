require "test_helper"

class GetPostToolTest < ActiveSupport::TestCase
  def call_tool(**arguments)
    delivered = JSON.parse(JSON.generate(arguments), symbolize_names: true)
    GetPostTool.call(**delivered, server_context: { user: @user })
  end

  setup do
    @user = User.create!(email_address: "agent@example.com", password: "password123")
  end

  test "returns the full post, including body" do
    post = Post.create!(content_type: :blog, title: "A Blog Post", body: "<p>Full content</p>")

    response = call_tool(id: post.id)

    data = JSON.parse(response.content.first[:text])
    assert_equal post.id, data["id"]
    assert_includes data["body"], "Full content"
  end

  test "includes status alongside published" do
    scheduled = Post.create!(content_type: :blog, title: "Scheduled Post", published_at: 3.days.from_now)

    response = call_tool(id: scheduled.id)

    data = JSON.parse(response.content.first[:text])
    assert_equal true, data["published"]
    assert_equal "scheduled", data["status"]
  end

  test "reads the body in the given locale" do
    post = Post.create!(content_type: :blog, title: "English", body: "<p>English body</p>")
    Mobility.with_locale(:de) { post.update!(body: "<p>Deutscher Text</p>") }

    response = call_tool(id: post.id, locale: "de")

    data = JSON.parse(response.content.first[:text])
    assert_includes data["body"], "Deutscher Text"
  end

  test "a locale outside the site's enabled languages returns an error response" do
    post = Post.create!(content_type: :blog, title: "A Blog Post")

    response = call_tool(id: post.id, locale: "fr")

    assert response.error?
  end

  test "returns an error response, not a crash, for a missing id" do
    response = call_tool(id: 999_999)

    assert response.error?
    assert_includes response.content.first[:text], "not found"
  end
end
