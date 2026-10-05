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
    with_singleton_override(StarterContents::EnsureHome, :call, ->(**) { raise StarterContent::Error, "StarterContent: boom" }) do
      result = as_owner { StarterContents::Add.call }

      assert_equal [ StarterContents::Add::FAILURE_MESSAGE ], result.errors
    end
    assert_not Audit::Event.exists?(action: "starter_content.added")
  end

  # Moved here from `StarterContentTest`, when the writing left the model.
  test "adds Blog, Resume and Now pages with one sample post each" do
    StarterContents::Add.call(locale: "en")

    home = Page.find_by(parent_id: nil)
    assert_equal %w[blog now resume], home.children.map(&:slug).sort
    assert_equal %w[blog now_update resume_entry], Post.pluck(:content_type).sort
    assert StarterContent.added?(locale: "en")
  end

  test "sample posts get JSON body documents in the given locale" do
    StarterContents::Add.call(locale: "de")

    Post.find_each do |post|
      assert_not post.body_document(locale: "de").blank?, "#{post.content_type} sample has no body"
      assert_empty post.body_document(locale: "de").validate
    end
  end

  test "writes in the given locale" do
    StarterContents::Add.call(locale: "de")

    assert Mobility.with_locale(:de) { Page.i18n.where(slug: "blog").exists? }
  end

  test "running it again in another locale creates nothing new" do
    StarterContents::Add.call(locale: "de")

    assert_no_difference [ "Page.count", "Post.count", "ContentBlock.count" ] do
      assert_equal false, StarterContents::Add.call(locale: "en").record
    end
  end

  test "after the sections were trashed, adding creates fresh ones beside them" do
    StarterContents::Add.call(locale: "en")
    home = Page.find_by(parent_id: nil)
    as_owner do
      home.children.each { |page| assert Trash::Move.call(page).ok? }
      Post.find_each { |post| assert Trash::Move.call(post).ok? }
    end

    assert_difference -> { Page.kept.count } => 3, -> { Post.kept.count } => 3 do
      assert_equal true, StarterContents::Add.call(locale: "en").record
    end
  end

  test "checks and creates under the site settings row lock" do
    statements = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, payload| statements << payload[:sql] }
    begin
      assert StarterContents::Add.call(locale: "en").record
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
    assert statements.any? { |sql| sql.include?(%(FROM "site_settings")) && sql.include?("FOR UPDATE") }
  end

  test "a write that fails rolls everything back and answers the failure message" do
    home = root_page
    failing = ->(**) {
      Pages::Save.call(attributes: { parent: home, published: true }, translations: { "en" => { title: "Half built" } })
      raise ActiveRecord::RecordNotUnique, "duplicate slug"
    }

    with_singleton_override(StarterContents::EnsureHome, :call, failing) do
      assert_no_difference [ "Page.count", "Post.count" ] do
        result = StarterContents::Add.call(locale: "en")
        assert_equal [ StarterContents::Add::FAILURE_MESSAGE ], result.errors
      end
    end
  end
end
