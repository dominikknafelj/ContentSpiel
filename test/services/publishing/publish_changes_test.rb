require "test_helper"

# Who may publish is the service contract's business
# (`test/services/service_behaviour_contract_test.rb`, its factory in
# `test/support/service_calls.rb`); this file is about what it writes.
class Publishing::PublishChangesTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "One")
    assert Pages::Save.call(@page, translations: { "en" => { title: "Two" } }).ok?
  end

  test "it takes the next copy from the rows and records who published which number" do
    result = Publishing::PublishChanges.call(@page)

    assert result.ok?, result.errors.to_sentence
    version = Publishing.current(@page)
    assert_equal 2, version.number
    assert_equal({ "en" => "Two" }, version.snapshot.dig("fields", "title"))
    event = Audit::Event.where(action: "page.changes_published").last
    assert_equal @page, event.subject
    assert_equal 2, event.metadata["number"]
    assert_equal false, event.metadata["scheduled"]
  end

  test "a post's event is post.changes_published" do
    post = create_post(title: "Post")

    assert Publishing::PublishChanges.call(post).ok?

    assert_equal post, Audit::Event.where(action: "post.changes_published").last.subject
  end

  test "at a time it leaves the site as it is until then, and the event says scheduled" do
    at = 2.days.from_now.change(usec: 0)

    assert Publishing::PublishChanges.call(@page, at: at).ok?

    assert_equal 1, Publishing.current(@page).number
    assert_equal at, Publishing.pending(@page).live_at
    assert_equal true, Audit::Event.where(action: "page.changes_published").last.metadata["scheduled"]
  end

  test "with no time given a pending copy is replaced and keeps its time; with a time it moves" do
    at = 2.days.from_now.change(usec: 0)
    assert Publishing::PublishChanges.call(@page, at: at).ok?
    assert Pages::Save.call(@page, translations: { "en" => { title: "Three" } }).ok?

    assert Publishing::PublishChanges.call(@page).ok?

    pending = Publishing.pending(@page)
    assert_equal at, pending.live_at
    assert_equal({ "en" => "Three" }, pending.snapshot.dig("fields", "title"))
    assert_equal 1, Publishing::Version.of(@page).pending.count

    assert Publishing::PublishChanges.call(@page, at: 5.days.from_now).ok?
    assert_operator Publishing.pending(@page).live_at, :>, at
  end

  test "a draft has nothing on the site to change: it fails, takes no copy and records nothing" do
    draft = create_page(title: "Draft", published: false)

    result = Publishing::PublishChanges.call(draft)

    assert_not result.ok?
    assert_not result.denied?
    assert_empty Publishing::Version.of(draft)
    assert_empty Audit::Event.where(action: "page.changes_published", subject: draft)
  end

  test "it takes the page's row lock before it reads anything of a copy" do
    statements = capture_sql { Publishing::PublishChanges.call(@page) }
    lock = statements.index { |sql| sql.match?(/FROM "pages".*FOR UPDATE/m) }
    first_copy_statement = statements.index { |sql| sql.include?("published_versions") }

    assert lock, "no row lock on the page"
    assert_operator lock, :<, first_copy_statement
  end
end
