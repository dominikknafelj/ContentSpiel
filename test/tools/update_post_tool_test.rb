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

  # `title: ""` alone already fails the presence validation, so it doesn't
  # tell apart the current single `assign_attributes` + `save!` from the old
  # two-step `update!(translated_attrs)` then `update!(published_at:)`: the
  # old code's *first* call would already raise on the empty title, before
  # its second call -- the one this test is actually about -- ever ran.
  #
  # Nothing in this app's validations legitimately couples title and
  # published_at, so to force a save that fails only when *both* are dirty
  # together (this app has no mocking gem), this temporarily overrides
  # Post#save! for the duration of the test and restores the original
  # afterwards. Under the old two-step code, the first `update!` call has
  # only the title dirty and the second only published_at, so the override
  # never trips and both changes go through -- which is exactly why the old
  # code isn't atomic. Under the current code, both are assigned before the
  # one `save!` call, so the override trips and neither change is persisted.
  test "atomicity: failed save rolls back title and published_at changes" do
    # A live post with a concrete (non-nil) published_at, so both assertions
    # below can be unconditional `assert_equal` -- the original test's
    # nil-vs-present branch obscured which branch, if any, was actually
    # exercised.
    original_title = @post.title
    original_published_at = 2.days.ago.change(usec: 0)
    @post.update!(published_at: original_published_at)

    Post.class_eval do
      alias_method :__original_save_bang_for_atomicity_test, :save!
      define_method(:save!) do |*args, **kwargs|
        raise ActiveRecord::RecordInvalid.new(self) if title_changed? && published_at_changed?

        __original_save_bang_for_atomicity_test(*args, **kwargs)
      end
    end

    begin
      # published: false alongside the title change so published_at is
      # genuinely dirty too (going from a set time to nil) -- unlike
      # published: true on an already-live post, which the tool assigns the
      # post's *own current* published_at, leaving it undirtied.
      response = call_tool(id: @post.id, title: "New Title", published: false)

      assert response.error?, "Tool should return an error when the combined save fails"

      @post.reload
      assert_equal original_title, @post.title,
        "Title should not have changed when the combined save fails"
      assert_equal original_published_at, @post.published_at,
        "Published_at should not have changed when the combined save fails"
    ensure
      Post.class_eval do
        alias_method :save!, :__original_save_bang_for_atomicity_test
        remove_method :__original_save_bang_for_atomicity_test
      end
    end
  end
end
