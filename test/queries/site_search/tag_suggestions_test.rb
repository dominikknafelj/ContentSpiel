require "test_helper"

# The tags a suggestion offers (search 2 spec §4.3): ContentSpiel's own,
# whatever the backend; the tags whose name begins with the prefix that a
# post live and visible now, with a current address in the language,
# carries in its copy in force.
class SiteSearch::TagSuggestionsTest < ActiveSupport::TestCase
  setup do
    @blog = create_page(title: "Blog")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: @blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).ok?
    publish_changes(@blog)
  end

  def tags_for(text, language: "en", limit: SiteSearch::SUGGEST_LIMIT, now: Time.current)
    SiteSearch::TagSuggestions.new(text: text, language: language, now: now, limit: limit).tags
  end

  def publish(post)
    assert Posts::Save.call(post.reload, attributes: { published: true }).ok? unless post.reload.published_at
    post
  end

  test "a tag that only drafts carry is not suggested" do
    create_post(title: "Draft", tags: %w[deployment], published: false)
    assert_empty tags_for("depl")
    publish(Post.last)
    assert_equal %w[deployment], tags_for("depl").map(&:name)
  end

  test "a tag prefix of % or _ suggests no tag that lacks it" do
    publish(create_post(title: "P", tags: %w[deployment 50%off]))
    assert_equal %w[50%off], tags_for("50%").map(&:name)
    assert_empty tags_for("_")
  end

  test "a tag is suggested in a language only when a post live in it carries it" do
    post = publish(create_post(title: "P", tags: %w[deployment]))
    PublicPath.where(record: post, locale: "de").delete_all # version: none (a test takes the post's German address away)
    assert_equal %w[deployment], tags_for("depl", language: "en").map(&:name)
    assert_empty tags_for("depl", language: "de")
  end

  test "a tag only the copy in force no longer holds, a scheduled post's tag and a hidden listing's are not suggested" do
    post = create_post(title: "P", tags: %w[deployment])
    assert Posts::Save.call(post.reload, attributes: { tag_names: %w[release] }).ok?
    assert_equal %w[deployment], tags_for("").map(&:name), "the rows changed, the copy in force did not"
    publish_changes(post)
    assert_equal %w[release], tags_for("").map(&:name)

    later = create_post(title: "Later", tags: %w[launch])
    Post.where(id: later.id).update_all(published_at: 1.day.from_now) # version: none (a test schedules the record around the services)
    assert_empty tags_for("laun")
    assert_equal %w[launch], tags_for("laun", now: 2.days.from_now).map(&:name)

    assert Pages::Save.call(@blog.reload, attributes: { published: false }).ok?
    assert_empty tags_for("")
  end

  test "ordered by name, case aside, cut to the limit, and matched by the start of the name" do
    publish(create_post(title: "P", tags: %w[delta deploy dev]))
    assert_equal %w[delta deploy], tags_for("de", limit: 2).map(&:name)
    assert_equal %w[dev], tags_for("DEV").map(&:name)
    assert_empty tags_for("eploy")
  end

  test "one statement, the prefix a bind" do
    publish(create_post(title: "P", tags: %w[zanzibar]))
    statements = []
    ActiveSupport::Notifications.subscribed(->(*, payload) { statements << payload[:sql] }, "sql.active_record") do
      assert_equal %w[zanzibar], tags_for("zanz").map(&:name)
    end
    assert_equal 1, statements.size
    refute statements.first.include?("zanz")
  end
end
