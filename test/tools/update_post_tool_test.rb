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

  test "re-publishing a live post keeps its published_at" do
    # Publish the post 3 days ago
    published_at = 3.days.ago.change(usec: 0)
    @post.update!(published_at: published_at)

    # Re-publish by setting published: true
    call_tool(id: @post.id, published: true)

    @post.reload
    assert_equal published_at, @post.published_at,
      "Re-publishing should keep the original published_at"
  end

  test "publishing a scheduled post makes it live now" do
    # Schedule the post for 3 days from now
    future_time = 3.days.from_now
    @post.update!(published_at: future_time)
    assert_equal "scheduled", @post.status

    # Publish by setting published: true
    response = call_tool(id: @post.id, published: true)

    @post.reload
    assert @post.live?, "Post should be live after publishing"
    # Published_at should be approximately now (within 1 second)
    assert_in_delta Time.current, @post.published_at, 1.second
    assert_equal "live", JSON.parse(response.content.first[:text])["status"]
  end

  test "atomicity: failed save rolls back title and published_at changes" do
    original_title = @post.title
    original_published_at = @post.published_at

    # Try to update title AND publish at the same time, but with an empty title that
    # violates the presence validation. This should fail before any database changes are made.
    response = call_tool(id: @post.id, title: "", published: true)

    assert response.error?, "Tool should return error when title is empty"

    # Verify that neither the title nor published_at changed in the DB.
    # Both should be rolled back because they're assigned and saved together.
    @post.reload
    assert_equal original_title, @post.title,
      "Title should not have changed due to save failure"
    if original_published_at.nil?
      assert_nil @post.published_at, "Published_at should remain nil after failed save"
    else
      assert_equal original_published_at, @post.published_at,
        "Published_at should not have changed due to save failure"
    end
  end
end
