require "test_helper"

class Posts::ListTest < ActiveSupport::TestCase
  setup do
    @me = users(:one)
    @live = as(@me) { create_post(title: "Live", published: true, tags: [ "rails" ]) }
    @draft = as(@me) { create_post(title: "Draft", published: false, tags: [ "ruby" ]) }
    @scheduled = as(@me) { create_post(title: "Scheduled", published: false) }
    as(@me) { assert Posts::Save.call(@scheduled, attributes: { published_at: 3.days.from_now }).ok? }
    @plain = as(@me) { create_post(title: "Plain draft", published: false) }
  end

  def list(filters = {}) = Posts::List.new(AccessControl.scope(@me, "posts.read", Post.all), filters: filters, locale: "en")

  def titles(list, limit: 50, offset: 0) = list.rows(limit: limit, offset: offset).map(&:title)

  test "the tag filter is the tag's stored name, and a post with another tag or none is left out" do
    assert_equal [ "Live" ], titles(list("tag" => "rails"))
    assert_empty titles(list("tag" => "Rails"))
    assert_equal({ "all" => 1, "live" => 1, "drafts" => 0, "scheduled" => 0 }, list("tag" => "rails").counts)
  end

  test "rows are the scope's, newest-changed first, and limit and offset page them" do
    @draft.update_columns(updated_at: 1.minute.from_now) # version: none (a test orders two rows by their change)
    assert_equal [ "Draft", "Plain draft" ], titles(list("scope" => "drafts"))
    assert_equal [ "Live" ], titles(list("scope" => "live"))
    assert_equal [ "Scheduled" ], titles(list("scope" => "scheduled"))

    everything = titles(list)
    assert_equal 4, everything.size
    assert_equal "Draft", everything.first
    assert_equal everything.first(2), titles(list, limit: 2)
    assert_equal everything.drop(2), titles(list, limit: 2, offset: 2)
  end

  test "counts ignore the scope and respect every other filter, in one statement" do
    counted = list("scope" => "live", "q" => "draft")
    assert_equal({ "all" => 2, "live" => 0, "drafts" => 2, "scheduled" => 0 }, counted.counts)
    assert_equal({ "all" => 4, "live" => 1, "drafts" => 2, "scheduled" => 1 }, list("scope" => "drafts").counts)

    fresh = list("scope" => "live", "type" => "blog")
    assert_queries_count(1) { fresh.counts }
  end

  test "a filter that is not a string is no filter, and an unknown scope is all" do
    [ { "tag" => [ "a" ], "scope" => "nope" }, { "status" => "drafts" }, { "scope" => "draft" } ].each do |filters|
      listed = list(filters)
      assert_equal "all", listed.scope_name, filters.inspect
      assert_equal 4, titles(listed).size, filters.inspect
    end
  end

  test "a trashed post is in no row and no count" do
    @draft.update_columns(trashed_at: Time.current) # version: none (a test puts a row in the trash around the callbacks)
    assert_not_includes titles(list), "Draft"
    assert_not_includes titles(list("scope" => "drafts")), "Draft"
    assert_equal({ "all" => 3, "live" => 1, "drafts" => 1, "scheduled" => 1 }, list.counts)
  end
end
