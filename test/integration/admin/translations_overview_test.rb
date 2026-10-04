require "test_helper"

# The Translations overview (translation helpers spec §4, Task 4):
# `Admin::TranslationsController#index` lists the readable pages, posts and
# images that are missing or outdated in one target language, grouped by
# type, each linking to its editor in that language -- plus the sidebar
# entry that leads there.
class Admin::TranslationsOverviewTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    with_locales(%w[en de es], default: "en")
    # The settings row has no `translation_states` rows until something
    # saves it (a record with no row reads complete): index it, so the matrix
    # has a Site settings row to show.
    Translations::StateIndex.rebuild_all
    sign_in_as(users(:one))
  end

  def complete_post(title)
    record = create_post(title: title)
    assert Posts::Save.call(record, translations: { "de" => { title: "#{title} (de)" }, "es" => { title: "#{title} (es)" } }).ok?
    record.reload
  end

  def outdated_post(title)
    record = complete_post(title)
    assert Posts::Save.call(record, translations: { "en" => { title: "#{title}!" } }).ok?
    record.reload
  end

  def complete_page(title)
    create_page(title: title, translations: { "de" => { title: "#{title} (de)" }, "es" => { title: "#{title} (es)" } })
  end

  def image_with_alt(alt, translations = {})
    asset = create_media_asset
    assert Media::Save.call(asset, translations: { "en" => { alt: alt } }.merge(translations)).ok?
    asset.reload
  end

  def row_id(type, record) = "translation-item-#{type}-#{record.id}"

  def sidebar_labels
    css_select("nav[aria-label='Modules'] section a").map { |link| link.at_css("span:not([data-badge])").text.strip }
  end

  def row(type, record) = "##{row_id(type, record)}"

  test "one matrix lists items needing work in any language, a chip per language linking to that editor tab" do
    missing_page = create_page(title: "Untranslated page")
    outdated_page = complete_page("Changed page")
    assert Pages::Save.call(outdated_page, translations: { "en" => { title: "Changed page!" } }).ok?
    stale_post = outdated_post("Stale post")
    image = image_with_alt("A cat")

    get "/cs-studio/translations"

    assert_response :success
    assert_select "h1", text: "Translations"
    assert_select "thead th[scope=col]", text: "Deutsch"
    assert_select "thead th[scope=col]", text: "Español"
    assert_select "#{row("page", missing_page)} th[scope=row] a[href='/cs-studio/pages/#{missing_page.id}?locale=de']", text: "Untranslated page"
    assert_select "#{row("page", missing_page)} [data-locale=de][data-translation-state=missing]"
    assert_select "#{row("page", missing_page)} [data-locale=es][data-translation-state=missing]"
    assert_select "#{row("page", missing_page)} td a", text: "Translate →"
    assert_select "#{row("page", outdated_page)} [data-locale=es][data-translation-state=outdated]"
    assert_select "#{row("page", outdated_page)} td a", text: "Review changes →"
    assert_select "#{row("post", stale_post)} a[href='/cs-studio/posts/#{stale_post.id}?locale=de'] [data-translation-state=outdated]"
    assert_select "#{row("media", image)} a[href='/cs-studio/media/#{image.id}?locale=es']"
    # One card per target language, none for the original.
    assert_select "[data-translation-summary] [data-locale]", count: 2
    assert_select "[data-translation-summary] [data-locale=en]", count: 0
  end

  test "rows with an outdated language come first, newest change first, then missing-only rows by updated_at" do
    old_missing = create_post(title: "Old missing")
    old_missing.update_columns(updated_at: 5.days.ago)
    new_missing = create_post(title: "New missing")
    older_outdated = outdated_post("Older outdated")
    older_outdated.update_columns(updated_at: 3.days.ago)
    newer_outdated = outdated_post("Newer outdated")
    newer_outdated.update_columns(updated_at: 1.day.ago)
    # The homepage is missing everywhere too; push it to the very end.
    Page.update_all(updated_at: 30.days.ago)

    get "/cs-studio/translations", params: { type: "post" }

    ids = css_select("tbody tr").map { |tr| tr["id"] }
    assert_equal [ newer_outdated, older_outdated, new_missing, old_missing ].map { |post| row_id("post", post) }, ids
  end

  test "the order also holds across types" do
    outdated = outdated_post("Outdated post")
    page = create_page(title: "Missing page")
    page.update_columns(updated_at: 1.hour.from_now)

    get "/cs-studio/translations"

    ids = css_select("tbody tr").map { |tr| tr["id"] }
    assert_operator ids.index(row_id("post", outdated)), :<, ids.index(row_id("page", page))
  end

  test "excludes complete and trashed items" do
    done = complete_post("Done post")
    trashed = create_post(title: "Trashed post")
    assert Trash::Move.call(trashed).ok?
    done_page = complete_page("Done page")
    done_image = image_with_alt("A dog", "de" => { alt: "Ein Hund" }, "es" => { alt: "Un perro" })
    trashed_image = image_with_alt("A bird")
    assert Trash::Move.call(trashed_image).ok?

    get "/cs-studio/translations"

    assert_response :success
    [ [ "post", done ], [ "post", trashed ], [ "page", done_page ], [ "media", done_image ], [ "media", trashed_image ] ].each do |type, record|
      assert_select row(type, record), count: 0
    end
  end

  test "a language that is done in an incomplete row is the solid chip and still links" do
    post = create_post(title: "Half done")
    assert Posts::Save.call(post, translations: { "de" => { title: "Halb fertig" } }).ok?

    get "/cs-studio/translations"

    assert_select "#{row("post", post)} a[href='/cs-studio/posts/#{post.id}?locale=de'] [data-translation-state=complete]"
    assert_select "#{row("post", post)} th[scope=row] a[href='/cs-studio/posts/#{post.id}?locale=es']"
  end

  test "summary cards count items over what the viewer can read" do
    complete_post("Done")
    create_post(title: "Not done")
    outdated_post("Stale")
    expected = Translations::StateIndex.summary("de", [ Page.kept, Post.kept, Media::Asset.kept ])

    get "/cs-studio/translations"

    assert_select "[data-translation-summary] [data-locale=de]" do
      assert_select "[role=progressbar][aria-valuenow='#{(expected[:complete] * 100.0 / expected[:total]).round}']"
      assert_select "span", text: /#{expected[:missing]} missing/
    end
    summary = Translations::StateIndex.summaries(%w[de es], [ Page.kept, Post.kept, Media::Asset.kept ])
    assert_equal expected, summary["de"].slice(:total, :complete, :missing, :outdated)
  end

  test "a section the matrix has nothing for says everything is translated" do
    Page.find_each { |page| assert Pages::Save.call(page, translations: { "de" => { title: "Startseite #{page.id}" }, "es" => { title: "Inicio #{page.id}" } }).ok? }
    Translations::State.where(record_type: "SiteSetting").update_all(state: "complete", missing_count: 0, outdated_count: 0)

    get "/cs-studio/translations"

    assert_response :success
    assert_select "tbody tr", count: 0
    assert_select "h3", text: "Everything is translated."
  end

  test "filters by type, the segments carrying counts" do
    page = create_page(title: "Untranslated page")
    post_record = create_post(title: "Untranslated post")

    get "/cs-studio/translations", params: { type: "post" }

    assert_response :success
    assert_select row("post", post_record)
    assert_select row("page", page), count: 0
    assert_select "input[name=type][value=post][checked]"
    assert_select "label", text: /Posts\s*1/
  end

  test "the Site settings row appears only for settings.manage and only while incomplete" do
    get "/cs-studio/translations"
    assert_select "#translation-item-settings th[scope=row] a[href='/cs-studio/settings?locale=de']", text: /Site settings/
    assert_select "label", text: /Site settings/

    sign_out
    sign_in_as(users(:reader))
    get "/cs-studio/translations"
    assert_response :success
    assert_select "#translation-item-settings", count: 0
    assert_select "label", text: /Site settings/, count: 0
  end

  test "an old ?locale= link is accepted and ignored" do
    post_record = create_post(title: "Anything")

    get "/cs-studio/translations", params: { locale: "de" }
    assert_response :success
    assert_select row("post", post_record)

    get "/cs-studio/translations", params: { locale: "xx", type: "post" }
    assert_response :success
    assert_select row("post", post_record)
  end

  test "is read-scoped: an author whose reads stop at their own posts doesn't see anyone else's, nor count them" do
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    access_control_grants(:author_posts_create).update!(scope: { "own" => true })
    own = create_post(title: "Own post")
    own.update_column(:author_id, users(:author).id)
    other = create_post(title: "Other post")
    other.update_column(:author_id, users(:two).id)
    sign_out
    sign_in_as(users(:author))

    get "/cs-studio/translations"

    assert_response :success
    assert_select row("post", own)
    assert_select row("post", other), count: 0
    assert_not_includes response.body, "Other post"
    scoped = Translations::StateIndex.summaries(%w[de], [ AccessControl.scope(users(:author), "posts.read", Post.all, channel: :admin) ]).fetch("de")
    assert_select "[data-translation-summary] [data-locale=de] [role=progressbar][aria-valuenow='#{(scoped[:complete] * 100.0 / scoped[:total]).round}']"
  end

  test "images are listed only for someone holding media.upload" do
    image = image_with_alt("A cat")
    sign_out
    sign_in_as(users(:reader))

    get "/cs-studio/translations"

    assert_response :success
    assert_select row("media", image), count: 0
    assert_select "label", text: /Images/, count: 0
  end

  test "pages through results, 50 per page, the settings row topping page 1 only" do
    posts = Array.new(51) { |index| create_post(title: "Post #{index}") }
    posts.each_with_index { |post, index| post.update_columns(updated_at: (index + 1).minutes.ago) }
    Page.update_all(updated_at: 30.days.ago)

    # 51 posts: one past a page.
    get "/cs-studio/translations"

    assert_response :success
    assert_select "tbody tr[id^='translation-item-']", count: Admin::TranslationsController::PER_PAGE + 1
    assert_select "tbody tr#translation-item-settings", count: 1
    assert_select "a", text: "Previous", count: 0
    assert_select "a[href*='page=2']", text: "Next"

    get "/cs-studio/translations", params: { page: 2 }

    assert_response :success
    assert_select "tbody tr[id^='translation-item-']", count: 1
    assert_select row("post", posts.last)
    assert_select "tbody tr#translation-item-settings", count: 0
    assert_select "a", text: "Next", count: 0
    assert_select "a", text: "Previous"
  end

  test "junk and out-of-range page numbers never error" do
    create_post(title: "One post")

    %w[0 abc -1].each do |junk|
      get "/cs-studio/translations", params: { page: junk }
      assert_response :success
    end
    get "/cs-studio/translations", params: { page: 9999 }
    assert_response :success
    assert_select "a", text: "Back to page 1"
  end

  test "a page of results runs across the types, in order, with a real total" do
    # 1 homepage + 48 pages, then 3 posts = 52 items (settings aside).
    48.times { |i| create_page(title: "Page #{i}") }
    posts = 3.times.map { |i| create_post(title: "Post #{i}") }
    Page.update_all(updated_at: 1.day.ago)
    posts.each { |post| post.update_columns(updated_at: 1.minute.ago) }

    get admin_translations_path(page: 2)
    assert_response :success
    assert_select "tbody tr[id^='translation-item-']", 2
    get admin_translations_path(page: 1)
    assert_select "tbody tr[id^='translation-item-']", 51 # 50 + the settings row
    posts.each { |post| assert_select row("post", post) }
  end

  test "the number of queries does not depend on the rows or the languages" do
    count_queries = lambda do
      queries = 0
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, payload| queries += 1 unless payload[:name] == "SCHEMA" }
      get "/cs-studio/translations"
      ActiveSupport::Notifications.unsubscribe(subscriber)
      assert_response :success
      assert_operator queries, :>, 0
      queries
    end
    5.times { |i| outdated_post("Few #{i}") }
    get "/cs-studio/translations" # warm lazily loaded things
    few = count_queries.call

    60.times { |i| i.even? ? create_post(title: "Many #{i}") : create_page(title: "Many page #{i}") }
    assert_equal few, count_queries.call, "more rows"

    with_locales(%w[en de es fr it], default: "en")
    count_queries.call # the first request after a language change loads the new languages' own settings
    assert_equal few, count_queries.call, "more languages"
  end

  test "with one language enabled there is nothing to translate into" do
    with_locales(%w[en], default: "en")

    get "/cs-studio/translations"

    assert_redirected_to "/cs-studio"
  end

  test "needs pages.read or posts.read" do
    sign_out
    sign_in_as(users(:editor_branch))

    get "/cs-studio/translations"

    assert_response :forbidden
  end

  test "the sidebar shows Translations with more than one language and a read right" do
    get "/cs-studio"

    assert_includes sidebar_labels, "Translations"
    assert_select "nav[aria-label='Modules'] a[href='/cs-studio/translations']", text: "Translations"
  end

  test "the sidebar hides Translations with one enabled language" do
    with_locales(%w[en], default: "en")

    get "/cs-studio"

    assert_response :success
    assert_not_includes sidebar_labels, "Translations"
  end

  test "the sidebar hides Translations without read rights" do
    sign_out
    sign_in_as(users(:editor_branch))

    get "/cs-studio"

    assert_response :success
    assert_not_includes sidebar_labels, "Translations"
  end
end
