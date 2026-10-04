require "test_helper"

# `GET /<admin>/users/suggest?q=` (`Admin::UserSuggestionsController`): the group
# editor's member chip input. Needs `groups.manage`; up to 8 users matching name
# or email, owners left out, nothing for a short query.
class Admin::UserSuggestionsTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:two))
  end

  def suggest(q, **headers) = get("/cs-studio/users/suggest", params: { q: q }, headers: headers) && response.parsed_body

  test "matches the email or the name, with the display name as label and the email as hint" do
    users(:reader).update_columns(name: "Rita Reader")

    by_email = suggest("author@")
    assert_equal [ { "value" => users(:author).id, "label" => "author@example.com", "hint" => "author@example.com" } ], by_email

    by_name = suggest("rita")
    assert_equal [ { "value" => users(:reader).id, "label" => "Rita Reader", "hint" => "reader@example.com" } ], by_name
  end

  test "owners are never offered" do
    assert_equal [], suggest("one@")
    assert_not_includes suggest("example.com").map { |row| row["value"] }, users(:one).id
  end

  test "prefix matches come before substring matches" do
    User.create!(email_address: "zed.author@example.com", password: "a-long-enough-password")

    assert_equal %w[author@example.com zed.author@example.com], suggest("author").map { |row| row["hint"] }
  end

  test "answers at most 8 rows" do
    10.times { |i| User.create!(email_address: "member#{i}@example.org", password: "a-long-enough-password") }

    assert_equal 8, suggest("member").size
  end

  test "a blank or one-letter query lists nobody: it is not a user directory" do
    assert_equal [], suggest("")
    assert_equal [], suggest("a")
    assert_equal [], suggest("  ")
  end

  test "% and _ are literal, and the text is bound, not interpolated" do
    User.create!(email_address: "a_b@example.org", password: "a-long-enough-password")
    User.create!(email_address: "axb@example.org", password: "a-long-enough-password")

    assert_equal [ "a_b@example.org" ], suggest("a_b").map { |row| row["hint"] }
    assert_equal [], suggest("%%")
    assert_equal [], suggest("x') OR 1=1 --")
  end

  test "a very long query is capped rather than refused" do
    get "/cs-studio/users/suggest", params: { q: "x" * 5000 }

    assert_response :success
    assert_empty response.parsed_body
  end

  test "without groups.manage it is a 403: JSON for the fetch, the 403 page otherwise" do
    sign_in_as(users(:author))

    get "/cs-studio/users/suggest", params: { q: "ex" }, headers: { "Accept" => "application/json" }
    assert_response :forbidden
    assert_equal [ "errors" ], response.parsed_body.keys

    get "/cs-studio/users/suggest", params: { q: "ex" }
    assert_response :forbidden
    assert_not_includes response.body, "reader@example.com"
  end

  test "the route is not read as a user id" do
    get "/cs-studio/users/suggest", params: { q: "ex" }

    assert_response :success
  end
end
