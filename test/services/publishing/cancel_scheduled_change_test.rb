require "test_helper"

# Who may cancel is the service contract's business
# (`test/services/service_behaviour_contract_test.rb`); this file is about
# what it writes.
class Publishing::CancelScheduledChangeTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "One")
    assert Pages::Save.call(@page, translations: { "en" => { title: "Two" } }).ok?
    publish_changes(@page, at: 2.days.from_now)
  end

  def cancel(record = @page)
    result = Publishing::CancelScheduledChange.call(record.reload)
    assert result.ok?, result.errors.to_sentence
  end

  test "the pending copy goes, the rows stay as they are and are unpublished changes again" do
    assert_equal :live_change_scheduled, Publishing::State.of(@page.reload).state
    assert_not @page.unpublished_changes?

    cancel

    assert_nil Publishing.pending(@page)
    assert_equal 1, Publishing.current(@page).number
    assert_equal "Two", Mobility.with_locale(:en) { @page.reload.title }
    assert @page.unpublished_changes?
    assert_equal :live_with_changes, Publishing::State.of(@page).state
    assert_equal %w[title], Publishing::Changes.of(@page).fields
  end

  test "it records one event with the number of the copy that was withdrawn" do
    cancel

    event = Audit::Event.where(action: "page.scheduled_change_cancelled").sole
    assert_equal @page, event.subject
    assert_equal({ "number" => 2 }, event.metadata)
  end

  test "a post's event is post.scheduled_change_cancelled" do
    post = create_post(title: "Post")
    assert Posts::Save.call(post, translations: { "en" => { title: "Changed" } }).ok?
    publish_changes(post, at: 1.day.from_now)

    cancel(post)

    assert_equal post, Audit::Event.where(action: "post.scheduled_change_cancelled").sole.subject
    assert post.reload.unpublished_changes?
  end

  test "where the rows are what is in force again, nothing is left to publish and the mark is cleared" do
    assert Pages::Save.call(@page, translations: { "en" => { title: "One" } }).ok?
    assert @page.reload.unpublished_changes?

    cancel

    assert_not @page.reload.unpublished_changes?
    assert_equal :live, Publishing::State.of(@page).state
  end

  test "nothing public moves: the content version, the addresses and the copy in force" do
    version = PublicSite.content_version
    paths = PublicPath.order(:id).pluck(:id, :locale, :path)

    cancel

    assert_equal version, PublicSite.content_version
    assert_equal paths, PublicPath.order(:id).pluck(:id, :locale, :path)
    assert_equal "One", Mobility.with_locale(:en) { Publishing.published(@page.reload).title }
  end

  test "an image only the withdrawn copy showed is no longer in use, and one the copy in force shows still is" do
    kept = create_media_asset
    assert ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "image", media_asset_id: kept.id }).ok?
    publish_changes(@page, at: Time.current) # now, not at the time the setup's change is scheduled for
    scheduled = create_media_asset
    block = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "image", media_asset_id: scheduled.id }).record
    publish_changes(@page, at: 2.days.from_now)
    assert ContentBlocks::Destroy.call(block).ok?
    assert Media::Usage.exists?(media_asset_id: scheduled.id, role: "published")

    cancel

    assert_empty Media::Usage.where(media_asset_id: scheduled.id)
    assert Media::Usage.exists?(media_asset_id: kept.id, owner: @page, role: "published")
  end

  test "with no change scheduled, and for a draft, there is nothing to cancel: nothing is written" do
    cancel
    draft = create_page(title: "Draft", published: false)
    events = Audit::Event.count

    result = Publishing::CancelScheduledChange.call(@page.reload)

    assert_not result.ok?
    assert_not result.denied?
    assert_equal [ "No change is scheduled" ], result.errors
    assert_not Publishing::CancelScheduledChange.call(draft).ok?
    assert_equal events, Audit::Event.count
  end

  test "it takes the record's row lock before it touches a copy" do
    statements = capture_sql { cancel }

    lock = statements.index { |sql| sql.match?(/FROM "pages".*FOR UPDATE/m) }
    first_copy = statements.index { |sql| sql.include?(%("published_versions")) }
    assert_operator lock, :<, first_copy
  end
end
