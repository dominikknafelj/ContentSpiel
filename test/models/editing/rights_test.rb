require "test_helper"

class Editing::RightsTest < ActiveSupport::TestCase
  setup do
    @draft = create_page(title: "Draft", published: false)
    @live = create_page(title: "Live", published: true)
    @draft_post = create_post(title: "Draft post", published: false)
    @live_post = create_post(title: "Live post", published: true)
  end

  def grant(*permissions)
    group = access_control_groups(:branch_editors)
    permissions.each { |key| AccessControl::Grant.create!(group:, permission: key, scope: {}) }
    users(:editor_branch)
  end

  # A page's block is saved by `ContentBlocks::Save`, a post's text by `Posts::Save`.
  def save_denied?(record)
    if record.is_a?(Page)
      ContentBlocks::Save.call(ContentBlock.new(owner: record), attributes: { block_type: "rich_text" }).denied?
    else
      Posts::Save.call(Post.find(record.id), attributes: {}, translations: { Locales.default => { title: "Renamed" } }).denied?
    end
  end

  test "an owner lacks nothing" do
    [ @draft, @live, @draft_post, @live_post ].each { |record| assert_nil Editing::Rights.missing(users(:one), record) }
  end

  test "a reader lacks edit" do
    assert_equal "pages.edit", Editing::Rights.missing(users(:reader), @draft)
    assert_equal "posts.edit", Editing::Rights.missing(users(:reader), @draft_post)
  end

  test "edit without publish lacks nothing on a draft and publish on a published page" do
    editor = grant("pages.edit")
    assert_nil Editing::Rights.missing(editor, @draft)
    assert_equal "pages.publish", Editing::Rights.missing(editor, @live)
  end

  test "the same for a post" do
    editor = grant("posts.edit")
    assert_nil Editing::Rights.missing(editor, @draft_post)
    assert_equal "posts.publish", Editing::Rights.missing(editor, @live_post)
  end

  test "it agrees with what the save services refuse, for the fixtures' actors" do
    editor = grant("pages.edit", "posts.edit")
    [ users(:one), users(:two), users(:author), users(:reader), editor ].each do |actor|
      [ @draft, @live, @draft_post, @live_post ].each do |record|
        refused = as(actor) { save_denied?(record) }
        assert_equal refused, Editing::Rights.missing(actor, record).present?, "#{actor.email_address} on #{record.class} #{record.id}"
      end
    end
  end
end
