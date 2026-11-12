require "test_helper"

class Jump::SearchTest < ActiveSupport::TestCase
  setup do
    @owner = users(:one)
    @modules = StudioModules.entries.map(&:to_row)
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
    assert_includes rows_of(groups).map { |row| row[:route] }, [ :admin_page_path, [ page ], {} ]
    assert_includes rows_of(groups).map { |row| row[:route] }, [ :admin_media_path, [], { selected: asset.id } ]
  end

  test "groups come in the order Pages, Posts, Media, Sections, Settings, Actions" do
    create_page(title: "Order page")
    create_post(title: "Order post")
    asset = create_media_asset
    asset.update!(title: "Order image")
    assert_equal %w[Pages Posts Media], search("order").map { |group| group[:label] }.first(3)
  end

  test "an empty query lists modules and actions only" do
    create_post(title: "Something")
    labels = search("").map { |group| group[:label] }
    assert_equal %w[Sections Settings Actions], labels
  end

  test "modules are listed under Sections, and Settings holds settings destinations" do
    groups = search("", actor: @owner)
    assert_includes groups.map { |g| g[:label] }, "Sections"
    settings = groups.find { |g| g[:label] == "Settings" }
    assert_includes settings[:rows].map { |r| r[:title] }, "Settings › Languages"
    assert_not_includes settings[:rows].map { |r| r[:title] }, "Dashboard"
    assert_equal Jump::Search::SETTINGS_TITLES.values, settings[:rows].map { |r| r[:title] }, "every section, in the nav's order"
    sections = groups.find { |g| g[:label] == "Sections" }
    assert_includes sections[:rows].map { |r| r[:title] }, "Dashboard"
  end

  test "settings destinations anchor into the Settings screen and need the permission their section needs" do
    settings = search("ai trans").find { |g| g[:label] == "Settings" }
    assert_equal [ "Settings › AI translation" ], settings[:rows].map { |r| r[:title] }
    assert_equal [ :admin_settings_path, [], { anchor: "ai" } ], settings[:rows].first[:route]

    languages = search("languages", actor: @owner).find { |g| g[:label] == "Settings" }
    assert_equal [ "Settings › Languages" ], languages[:rows].map { |r| r[:title] }
    assert_equal [ :admin_settings_path, [], { anchor: "languages" } ], languages[:rows].first[:route]

    nobody = User.create!(email_address: "nobody3@example.com", password: "a long enough password")
    assert_nil search("", actor: nobody, modules: []).find { |g| g[:label] == "Settings" }
  end

  test "the Settings rows are SettingsSections', titled one each" do
    assert_equal SettingsSections.ids, Jump::Search::SETTINGS_TITLES.keys
    assert_equal [ "Settings › Site", "Settings › Languages", "Settings › Publishing", "Settings › Forms", "Settings › AI translation",
      "Settings › Mail", "Settings › Sign-in", "Settings › Images" ], Jump::Search::SETTINGS_TITLES.values

    %w[forms mail images].each do |id|
      rows = search(Jump::Search::SETTINGS_TITLES.fetch(id).delete_prefix("Settings › ")).find { |g| g[:label] == "Settings" }[:rows]
      assert_includes rows, { title: Jump::Search::SETTINGS_TITLES.fetch(id), route: [ :admin_settings_path, [], { anchor: id } ] }
    end

    languages_only = users(:editor_branch)
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "languages.manage", scope: {})
    AccessControl::Membership.create!(user: languages_only, group: access_control_groups(:branch_editors)) unless languages_only.groups.exists?(access_control_groups(:branch_editors).id)
    assert_not AccessControl.holds?(languages_only, "settings.manage", channel: :admin), "the premise: the viewer holds languages.manage alone"
    settings = search("", actor: languages_only, modules: []).find { |g| g[:label] == "Settings" }
    assert_equal [ "Settings › Languages" ], settings[:rows].map { |r| r[:title] }
  end

  test "a blank query by a viewer who holds every permission lists all eight Settings rows, past the group limit" do
    assert SettingsSections::ALL.all? { |section| AccessControl.holds?(@owner, section.permission, channel: :admin) }, "the premise: the owner holds every section's right"
    assert_operator SettingsSections.ids.size, :>, Jump::Search::LIMIT, "the premise: there are more sections than the limit"

    settings = search("").find { |g| g[:label] == "Settings" }
    assert_equal SettingsSections.ids, settings[:rows].map { |r| r[:route].last[:anchor] }
    assert_equal SettingsSections.ids.map { |id| Jump::Search::SETTINGS_TITLES.fetch(id) }, settings[:rows].map { |r| r[:title] }

    7.times { |i| create_post(title: "Limited #{i}") }
    assert_equal Jump::Search::LIMIT, search("limited").find { |g| g[:label] == "Posts" }[:rows].size, "the open-ended groups keep the limit"
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
    open_modules = StudioModules.entries.select { |entry| entry.permission.nil? }.map(&:to_row)
    rows = rows_of(search("", actor: nobody, modules: open_modules)).map { |row| row[:title] }
    assert_includes rows, "Dashboard"
    assert_not_includes rows, "Users"
    assert_not_includes rows, "New page"
  end

  test "a short query matches titles, not locale keys: an older real match still appears behind newer non-matches" do
    older = create_post(title: "Garden notes")
    older.update_columns(title: { "en" => "Garden notes", "de" => "Gartenbuch" }, updated_at: 1.day.ago)
    25.times { |i| create_post(title: "Filler #{i}") }
    # "de" is a locale key of every record's title, and a substring of the
    # older record's German title only.
    assert_equal [ "Garden notes" ], rows_of(content_groups(search("de"))).map { |row| row[:title] }
  end

  test "a title containing a double quote is found by a query containing one" do
    create_post(title: 'The "quoted" one')
    assert_equal [ 'The "quoted" one' ], rows_of(content_groups(search('"quoted"'))).map { |row| row[:title] }
  end

  test "a backslash query matches a title containing a backslash" do
    create_post(title: 'C:\\temp')
    assert_nothing_raised { search("\\") }
    assert_equal [ 'C:\\temp' ], rows_of(content_groups(search("\\"))).map { |row| row[:title] }
  end
end
