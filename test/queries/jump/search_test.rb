require "test_helper"

class Jump::SearchTest < ActiveSupport::TestCase
  setup do
    @owner = users(:one)
    @modules = Admin::BaseController::MODULES
  end

  def search(query, actor: @owner, modules: @modules) = Jump::Search.new(actor: actor, query: query, modules: modules).groups
  def rows_of(groups) = groups.flat_map { |group| group[:rows] }
  def content_groups(groups) = groups.select { |group| %w[Pages Posts Media].include?(group[:label]) }

  test "matches post titles case-insensitively, five per group" do
    7.times { |i| create_post(title: "Jumpable #{i}") }
    posts = search("jumpABLE").find { |group| group[:label] == "Posts" }
    assert_equal 5, posts[:rows].size
    assert posts[:rows].all? { |row| row[:title].start_with?("Jumpable") }
  end

  test "matches page titles and library images" do
    page = create_page(title: "Quokka page")
    asset = create_media_asset
    asset.update!(title: "Quokka picture")
    groups = search("quokka")
    assert_equal %w[Pages Media], groups.map { |group| group[:label] } & %w[Pages Media]
    assert_includes rows_of(groups).map { |row| row[:url] }, Rails.application.routes.url_helpers.admin_page_path(page)
    assert_includes rows_of(groups).map { |row| row[:url] }, Rails.application.routes.url_helpers.admin_medium_path(asset)
  end

  test "groups come in the order Pages, Posts, Media, Settings, Actions" do
    create_page(title: "Order page")
    create_post(title: "Order post")
    asset = create_media_asset
    asset.update!(title: "Order image")
    assert_equal %w[Pages Posts Media], search("order").map { |group| group[:label] }.first(3)
  end

  test "an empty query lists modules and actions only" do
    create_post(title: "Something")
    labels = search("").map { |group| group[:label] }
    assert_equal %w[Settings Actions], labels
  end

  test "a two-letter query does not match a record through a locale key" do
    create_post(title: "Unrelated")
    assert_empty content_groups(search("de"))
    assert_empty content_groups(search("en"))
  end

  test "LIKE wildcards are literal text, not match-everything" do
    create_post(title: "Plain title")
    assert_empty content_groups(search("%"))
    assert_empty content_groups(search("_"))
    assert_nothing_raised { search("\\") }
    assert_empty content_groups(search("\\"))
    create_post(title: "100% sure")
    assert_equal [ "100% sure" ], rows_of(content_groups(search("%"))).map { |row| row[:title] }
  end

  test "an overlong query is cut to 100 characters instead of failing" do
    assert_nothing_raised { search("a" * 500) }
    create_post(title: "a" * 100)
    assert_equal 1, rows_of(content_groups(search("a" * 500))).size
  end

  test "trashed records and records outside the viewer's scope never appear" do
    visible = create_post(title: "Findme kept")
    gone = create_post(title: "Findme trashed")
    gone.update!(trashed_at: Time.current)
    titles = rows_of(search("findme")).map { |row| row[:title] }
    assert_equal [ visible.title ], titles

    nobody = User.create!(email_address: "nobody@example.com", password: "a long enough password")
    assert_empty rows_of(content_groups(search("findme", actor: nobody, modules: [])))
  end

  test "modules and actions are limited to what the viewer may open" do
    nobody = User.create!(email_address: "nobody2@example.com", password: "a long enough password")
    open_modules = Admin::BaseController::MODULES.select { |entry| entry[:permission].nil? }
    rows = rows_of(search("", actor: nobody, modules: open_modules)).map { |row| row[:title] }
    assert_includes rows, "Dashboard"
    assert_not_includes rows, "Users"
    assert_not_includes rows, "New page"
  end
end
