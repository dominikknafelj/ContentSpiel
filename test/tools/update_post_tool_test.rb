require "test_helper"

class UpdatePostToolTest < ActiveSupport::TestCase
  def call_tool(**arguments)
    delivered = JSON.parse(JSON.generate(arguments), symbolize_names: true)
    UpdatePostTool.call(**delivered, server_context: { user: @user })
  end

  setup do
    @user = User.create!(email_address: "agent@example.com", password: "password123")
    @post = Post.create!(content_type: :blog, title: "Original Title", body: "<p>Original body</p>",
      excerpt: "Original excerpt")
  end

  test "updates only the fields given, leaving the rest alone" do
    call_tool(id: @post.id, title: "New Title")

    @post.reload
    assert_equal "New Title", @post.title
    assert_includes @post.body.to_s, "Original body"
    assert_equal "Original excerpt", @post.excerpt
  end

  test "updates the body" do
    call_tool(id: @post.id, body: "<p>New body</p>")

    assert_includes @post.reload.body.to_s, "New body"
  end

  test "published: true publishes a draft" do
    call_tool(id: @post.id, published: true)

    assert @post.reload.published_at.present?
  end

  test "published: false unpublishes" do
    @post.update!(published_at: Time.current)

    call_tool(id: @post.id, published: false)

    assert_nil @post.reload.published_at
  end

  test "omitting published leaves the current publish state alone" do
    @post.update!(published_at: Time.current)

    call_tool(id: @post.id, title: "New Title")

    assert @post.reload.published_at.present?
  end

  test "writes to the given locale, leaving other locales alone" do
    call_tool(id: @post.id, title: "Deutscher Titel", locale: "de")

    assert_equal "Deutscher Titel", Mobility.with_locale(:de) { @post.reload.title }
    assert_equal "Original Title", Mobility.with_locale(:en) { @post.title }
  end

  test "returns an error response, not a crash, for a missing id" do
    response = call_tool(id: 999_999, title: "New Title")

    assert response.error?
    assert_includes response.content.first[:text], "not found"
  end
end
