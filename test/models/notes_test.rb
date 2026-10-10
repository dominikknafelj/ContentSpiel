require "test_helper"

class NotesTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @post = create_post(title: "Hello")
    @asset = create_media_asset
    @nobody = User.create!(email_address: "nobody@example.com", password: "a-long-password-1")
  end

  def thread_on(subject) = Notes::Thread.create!(subject: subject, last_message_at: Time.current)

  test "a key is the class without colons and the id" do
    block = @page.content_blocks.create!(block_type: "rich_text", position: 0)

    assert_equal "Page-#{@page.id}", Notes.key(@page)
    assert_equal "ContentBlock-#{block.id}", Notes.key(block)
    assert_equal "MediaAsset-#{@asset.id}", Notes.key(@asset)
    assert_equal "MediaAsset-5", Notes.key("Media::Asset", 5)
  end

  test "the keys follow the container" do
    assert_equal %w[pages.read posts.read media.upload], [ @page, @post, @asset ].map { |record| Notes.read_key(record) }
    assert_equal %w[pages.edit posts.edit media.manage], [ @page, @post, @asset ].map { |record| Notes.moderate_key(record) }
  end

  test "a reader reads and does not moderate; an uploader moderates their own image; a stranger does neither" do
    assert Notes.readable?(users(:reader), @page, channel: :admin)
    assert_not Notes.moderator?(users(:reader), @page, channel: :admin)
    assert Notes.moderator?(users(:two), @page, channel: :admin)
    assert_not Notes.readable?(@nobody, @page, channel: :admin)
    assert_not Notes.readable?(@nobody, @asset, channel: :admin)

    @asset.update_columns(created_by_id: users(:author).id)
    AccessControl::Grant.create!(group: access_control_groups(:author), permission: "media.upload", scope: {}) unless AccessControl.holds?(users(:author), "media.upload", channel: :admin)
    assert Notes.moderator?(users(:author), @asset, channel: :admin)
    assert_not Notes.moderator?(users(:author), create_media_asset, channel: :admin)
  end

  test "readable_threads hides what the actor can't read and what is in the trash" do
    kept = [ thread_on(@page), thread_on(@post), thread_on(@asset) ]
    gone_page = create_page(title: "Gone")
    gone = thread_on(gone_page)
    gone_page.update!(trashed_at: Time.current)

    assert_equal kept.map(&:id).sort, Notes.readable_threads(users(:one), channel: :admin).pluck(:id).sort
    assert_not_includes Notes.readable_threads(users(:one), channel: :admin), gone
    assert_empty Notes.readable_threads(@nobody, channel: :admin)
    # Read only reads pages and posts and holds no media right.
    assert_equal kept.first(2).map(&:id).sort, Notes.readable_threads(users(:reader), channel: :admin).pluck(:id).sort
  end
end
