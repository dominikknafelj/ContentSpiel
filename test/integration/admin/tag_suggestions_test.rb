require "test_helper"

# `GET /<admin>/tags/suggest?q=` (`Admin::TagSuggestionsController`): the chip
# input's autocomplete for tags. Up to 8 names, prefix matches before
# substring matches, with the number of kept, readable posts using each.
class Admin::TagSuggestionsTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
  end

  def suggest(q) = get("/cs-studio/tags/suggest", params: { q: q }) && response.parsed_body

  test "prefix matches come before substring matches, case-insensitively, with counts" do
    create_post(title: "A", tags: [ "rails" ])
    create_post(title: "B", tags: [ "rails", "ruby-on-rails" ])
    create_post(title: "C", tags: [ "trailing" ])

    result = suggest("RA")

    assert_equal %w[rails ruby-on-rails trailing], result.map { |row| row["value"] }
    assert_equal({ "value" => "rails", "label" => "rails", "hint" => "2 posts" }, result.first)
    assert_equal "1 post", result.last["hint"]
  end

  test "an empty query lists the most used tags" do
    create_post(title: "A", tags: [ "common" ])
    create_post(title: "B", tags: [ "common", "rare" ])

    assert_equal %w[common rare], suggest("").map { |row| row["value"] }.first(2)
  end

  test "answers at most 8 rows" do
    12.times { |i| Tag.create!(name: "tag#{i}") }

    assert_equal 8, suggest("tag").size
  end

  test "% and _ are literal" do
    Tag.create!(name: "100%")
    Tag.create!(name: "a_b")
    Tag.create!(name: "axb")

    assert_equal [ "100%" ], suggest("%").map { |row| row["value"] }
    assert_equal [ "a_b" ], suggest("a_").map { |row| row["value"] }
  end

  test "a very long query is capped rather than refused" do
    Tag.create!(name: "rails")

    get "/cs-studio/tags/suggest", params: { q: "x" * 5000 }

    assert_response :success
    assert_empty response.parsed_body
  end

  test "a tag used only by trashed posts still appears, counted as 0" do
    create_post(title: "Gone", tags: [ "ghost" ]).update_columns(trashed_at: Time.current)

    assert_equal [ { "value" => "ghost", "label" => "ghost", "hint" => "0 posts" } ], suggest("gho")
  end

  test "counts cover only posts the viewer can read" do
    create_post(title: "Blog", tags: [ "scoped" ])
    create_post(title: "Now", content_type: "now_update", tags: [ "scoped" ])
    access_control_grants(:read_only_posts_read).update!(scope: { "content_types" => [ "now_update" ] })
    sign_in_as(users(:reader))

    assert_equal "1 post", suggest("scoped").first["hint"]
  end

  test "signed out redirects to sign-in" do
    reset!
    get "/cs-studio/tags/suggest", params: { q: "a" }

    assert_response :redirect
  end

  test "a user without posts.read is refused" do
    sign_in_as(users(:editor_branch))

    get "/cs-studio/tags/suggest", params: { q: "a" }

    assert_response :forbidden
  end
end
