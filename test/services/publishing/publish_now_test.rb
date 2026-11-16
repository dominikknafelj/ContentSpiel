require "test_helper"

# Who may publish is the service contract's business; this file is what each
# choice of "Publish now" writes on a scheduled record (D9).
class Publishing::PublishNowTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "One", published: false)
    assert Pages::Save.call(@page, attributes: { published_at: 2.days.from_now }).ok?
    assert Pages::Save.call(@page, translations: { "en" => { title: "Two" } }).ok?
  end

  def title_on_site = Mobility.with_locale(:en) { Publishing.published(@page.reload).title }

  test "publish now without the changes puts the scheduled copy on the site and leaves the later edits unpublished" do
    result = Publishing::PublishNow.call(@page)

    assert result.ok?, result.errors.to_sentence
    assert_equal false, result.value[:with_changes]
    assert_equal "live", @page.reload.status
    assert_equal "One", title_on_site
    assert_equal 1, Publishing::Version.of(@page).count
    assert @page.unpublished_changes_at
  end

  test "publish now with the changes puts the rows on the site at once and keeps the scheduled copy as an older version" do
    result = Publishing::PublishNow.call(@page, with_changes: true)

    assert result.ok?, result.errors.to_sentence
    assert_equal true, result.value[:with_changes]
    assert_equal "live", @page.reload.status
    assert_equal "Two", title_on_site
    assert_equal 2, Publishing::Version.of(@page).count
    assert_nil @page.unpublished_changes_at
    assert_equal 2, Publishing.current(@page).number
  end

  test "with a change scheduled as well, publishing with the changes withdraws the pending copy" do
    assert Publishing::PublishChanges.call(@page.reload, at: 3.days.from_now).ok?
    assert Pages::Save.call(@page, translations: { "en" => { title: "Three" } }).ok?
    assert Publishing.pending(@page)

    assert Publishing::PublishNow.call(@page.reload, with_changes: true).ok?

    assert_nil Publishing.pending(@page)
    assert_equal "Three", title_on_site
    assert_equal 2, Publishing::Version.of(@page).count # the scheduled copy and the one taken now
  end

  test "a change scheduled and nothing typed since is published now too" do
    assert Publishing::PublishChanges.call(@page.reload, at: 3.days.from_now).ok?

    assert Publishing::PublishNow.call(@page.reload, with_changes: true).ok?

    assert_nil Publishing.pending(@page)
    assert_equal "Two", title_on_site
  end

  test "a schedule moved since the dialog was read is refused and nothing is written" do
    copies = Publishing::Version.of(@page).count
    published_at = @page.published_at

    result = Publishing::PublishNow.call(@page, with_changes: true, shown_pending: 12345)

    assert_not result.ok?
    assert_equal [ Publishing::ShownSchedule::MOVED ], result.errors
    assert_equal copies, Publishing::Version.of(@page).count
    assert_equal published_at, @page.reload.published_at
  end

  test "the pending copy the dialog showed is accepted" do
    assert Publishing::PublishChanges.call(@page.reload, at: 3.days.from_now).ok?

    result = Publishing::PublishNow.call(@page.reload, with_changes: true, shown_pending: Publishing.pending(@page).id)

    assert result.ok?, result.errors.to_sentence
  end

  test "on a draft both choices are today's publish" do
    draft = create_page(title: "Draft", published: false)

    result = Publishing::PublishNow.call(draft, with_changes: true)

    assert result.ok?, result.errors.to_sentence
    assert_equal false, result.value[:with_changes]
    assert_equal "live", draft.reload.status
  end

  test "a post is published the same way" do
    post = create_post(title: "One", published: false)
    assert Posts::Save.call(post, attributes: { published_at: 2.days.from_now }).ok?
    assert Posts::Save.call(post, translations: { "en" => { title: "Two" } }).ok?

    assert Publishing::PublishNow.call(post, with_changes: true).ok?

    assert_equal "Two", Mobility.with_locale(:en) { Publishing.published(post.reload).title }
  end
end
