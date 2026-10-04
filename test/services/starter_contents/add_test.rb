require "test_helper"

class StarterContents::AddTest < ActiveSupport::TestCase
  test "adds the starter content once and records starter_content.added" do
    first = as_owner { StarterContents::Add.call }
    assert first.ok?, first.errors.inspect
    assert_equal true, first.record
    assert Audit::Event.exists?(action: "starter_content.added")
    assert Audit::Event.exists?(action: "page.created")

    second = as_owner { StarterContents::Add.call }
    assert second.ok?
    assert_equal false, second.record
    assert_equal 1, Audit::Event.where(action: "starter_content.added").count
  end

  test "the setup channel with no actor may add it" do
    assert as(nil, channel: :setup) { StarterContents::Add.call }.ok?
  end

  test "an Editor (pages and posts, unscoped) may add it" do
    editor = User.create!(email_address: "editor@example.com", password: "password12345")
    AccessControl::Membership.create!(user: editor, group: access_control_groups(:editor))

    assert as(editor) { StarterContents::Add.call }.ok?
  end

  test "is refused up front, before anything is written, without the rights it needs" do
    result = nil
    assert_no_difference [ "Page.count", "Post.count" ] do
      result = as(users(:reader)) { StarterContents::Add.call }
    end

    assert_not result.ok?
    assert Audit::Event.exists?(action: "access.denied")
  end

  test "a failure inside becomes a failed result, not an exception" do
    with_singleton_override(StarterContent, :create_pages_and_posts!, ->(**) { raise StarterContent::Error, "StarterContent: boom" }) do
      result = as_owner { StarterContents::Add.call }

      assert_equal [ StarterContents::Add::FAILURE_MESSAGE ], result.errors
    end
    assert_not Audit::Event.exists?(action: "starter_content.added")
  end
end
