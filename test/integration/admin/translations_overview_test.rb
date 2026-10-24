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
    assert_select "#{row("page", missing_page)} .admin-translation-row__action", text: "Translate →"
    assert_select "#{row("page", outdated_page)} [data-locale=es][data-translation-state=outdated]"
    assert_select "#{row("page", outdated_page)} .admin-translation-row__action", text: "Review changes →"
    assert_select "#{row("post", stale_post)} a[href='/cs-studio/posts/#{stale_post.id}?locale=de'] [data-translation-state=outdated]"
    assert_select "#{row("media", image)} a[href='/cs-studio/media?locale=es&selected=#{image.id}']"
    # One card per target language, none for the original.
    assert_select "[data-translation-summary] [data-locale]", count: 2
    assert_select "[data-translation-summary] [data-locale=en]", count: 0
  end

  test "rows with an outdated language come first, newest change first, then missing-only rows by updated_at" do
    old_missing = create_post(title: "Old missing")
    old_missing.update_columns(updated_at: 5.days.ago)
    new_missing = create_post(title: "New missing")
    older_outdated = outdated_post("Older outdated")
    original_changed(older_outdated, 3.days.ago)
    newer_outdated = outdated_post("Newer outdated")
    original_changed(newer_outdated, 1.day.ago)
    # The homepage is missing everywhere too; push it to the very end.
    Page.update_all(updated_at: 30.days.ago)

    get "/cs-studio/translations", params: { type: "post" }

    ids = css_select("tbody tr").map { |tr| tr["id"] }
    assert_equal [ newer_outdated, older_outdated, new_missing, old_missing ].map { |post| row_id("post", post) }, ids
  end

  # "Outdated first, the most recently changed ORIGINAL first" (handoff §4.4):
  # the time each original last changed is stored per field
  # (`translation_original_changed_at`); `updated_at` moves on any save.
  def original_changed(record, time)
    record.update_columns(translation_original_changed_at: { "title" => time.utc.iso8601 }, updated_at: Time.current)
  end

  def order_of(**params)
    get "/cs-studio/translations", params: params
    css_select("tbody tr[id^='translation-item-']").map { |tr| tr["id"] }
  end

  test "a translation-only save does not reorder the outdated rows" do
    older = outdated_post("Older original")
    newer = outdated_post("Newer original")
    original_changed(older, 3.days.ago)
    original_changed(newer, 1.day.ago)
    assert_equal [ newer, older ].map { |post| row_id("post", post) }, order_of(type: "post")

    # Translating the older post's German title is a save (updated_at moves)
    # but changes no original; Spanish keeps it outdated.
    assert Posts::Save.call(older, translations: { "de" => { title: "Älteres Original" } }).ok?
    assert_operator older.reload.updated_at, :>, newer.reload.updated_at

    assert_equal [ newer, older ].map { |post| row_id("post", post) }, order_of(type: "post")
  end

  test "a newer original change moves a row to the top, and a Confirm elsewhere moves nothing" do
    first = outdated_post("First")
    second = outdated_post("Second")
    original_changed(first, 3.days.ago)
    original_changed(second, 1.day.ago)
    assert_equal [ second, first ].map { |post| row_id("post", post) }, order_of(type: "post")

    original_changed(first, 1.hour.ago)

    assert_equal [ first, second ].map { |post| row_id("post", post) }, order_of(type: "post")
  end

  test "a block's original changing more recently counts for its page" do
    quiet = complete_page("Quiet page")
    assert Pages::Save.call(quiet, translations: { "en" => { title: "Quiet page!" } }).ok?
    busy = complete_page("Busy page")
    assert Pages::Save.call(busy, translations: { "en" => { title: "Busy page!" } }).ok?
    quiet.update_columns(translation_original_changed_at: { "title" => 2.days.ago.utc.iso8601 })
    busy.update_columns(translation_original_changed_at: { "title" => 4.days.ago.utc.iso8601 })
    quiet.update_columns(updated_at: 1.minute.from_now) # a plain updated_at order would put quiet first
    block = ContentBlock.create!(owner: busy, block_type: "rich_text", position: 1)
    block.update_columns(translation_original_changed_at: { "caption" => 1.hour.ago.utc.iso8601 })

    ids = order_of(type: "page")

    assert_equal [ busy, quiet ].map { |page| row_id("page", page) }, ids.first(2)
  end

  test "a malformed stored timestamp never breaks the screen" do
    post = outdated_post("Odd")
    post.update_columns(translation_original_changed_at: { "title" => "not a time", "excerpt" => "2026-13-45T99:99:99Z" })

    assert_includes order_of(type: "post"), row_id("post", post)
    assert_response :success
  end

  test "outdated-first order is stable across a page boundary and across types" do
    posts = Array.new(30) { |i| outdated_post("Stale post #{i}") }
    pages = Array.new(30) do |i|
      page = complete_page("Stale page #{i}")
      assert Pages::Save.call(page, translations: { "en" => { title: "Stale page #{i}!" } }).ok?
      page
    end
    (posts + pages).each_with_index { |record, i| record.update_columns(translation_original_changed_at: { "title" => (i + 1).hours.ago.utc.iso8601 }) }
    # Unrelated saves must not matter.
    posts.each { |post| post.update_columns(updated_at: Time.current) }
    expected = (posts + pages).sort_by { |record| record.reload.translation_original_changed_at["title"] }.reverse.map { |record| row_id(record.is_a?(Post) ? "post" : "page", record) }

    page_one = order_of(page: 1).reject { |id| id == "translation-item-settings" }
    page_two = order_of(page: 2)

    assert_equal expected.first(50), page_one
    assert_equal expected.drop(50), page_two.first(expected.size - 50)
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
    # An image whose original has no alt has nothing to translate: it is
    # complete in every language, so the matrix leaves it out (review C, M22 --
    # through `StateIndex` and the matrix, not only the model).
    no_alt = create_media_asset

    get "/cs-studio/translations"

    assert_response :success
    [ [ "post", done ], [ "post", trashed ], [ "page", done_page ], [ "media", done_image ], [ "media", trashed_image ], [ "media", no_alt ] ].each do |type, record|
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

  test "a summary card links to the matrix narrowed to its language, keeping the type filter" do
    both = create_post(title: "Needs both")
    only_es = create_post(title: "Only Spanish left")
    assert Posts::Save.call(only_es, translations: { "de" => { title: "Nur Spanisch" } }).ok?

    get "/cs-studio/translations", params: { type: "post" }
    assert_select "[data-translation-summary] [data-locale=de] a[href='/cs-studio/translations?language=de&type=post']", text: "Deutsch"
    assert_select "[data-translation-summary] [data-locale=de] a[aria-label='Deutsch: show items to translate']"

    get "/cs-studio/translations", params: { type: "post", language: "de" }
    assert_response :success
    assert_select row("post", both)
    assert_select row("post", only_es), count: 0
    assert_select "tbody th[scope=col]", count: 0
    assert_select "thead th[scope=col]", text: "Español" # every column stays
    assert_select "[data-translation-summary] [data-locale=de] a[aria-current=true][href='/cs-studio/translations?type=post']"
    assert_select "input[type=hidden][name=language][value=de]"
    assert_select "a", text: "Clear"

    get "/cs-studio/translations", params: { language: "xx" }
    assert_response :success
    assert_select row("post", only_es)
  end

  # Review C, M8 (spec §4): "Clear" only while a filter is active.
  test "Clear appears only when a language or a type filter is active, and leads to the unfiltered matrix" do
    create_post(title: "Needs work")
    get "/cs-studio/translations"
    assert_select "a", text: "Clear", count: 0

    [ { language: "de" }, { type: "post" } ].each do |params|
      get "/cs-studio/translations", params: params
      assert_select "a[href='/cs-studio/translations']", text: "Clear"
    end
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
    queries_for_request = lambda do
      statements = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, payload| statements << payload[:sql] unless payload[:name] == "SCHEMA" }
      get "/cs-studio/translations"
      ActiveSupport::Notifications.unsubscribe(subscriber)
      assert_response :success
      statements
    end
    5.times { |i| outdated_post("Few #{i}") }
    # The first request after anything that rewrites `site_settings` (the very
    # first of a process, and `with_locales`, which saves the languages) also
    # runs the setup-complete check (`SELECT 1 FROM site_settings WHERE
    # setup_completed_at IS NOT NULL`, then remembered): one query, shown by
    # diffing the statements, that has nothing to do with this screen. Each
    # measurement therefore follows an unmeasured request.
    get "/cs-studio/translations"
    few = queries_for_request.call

    60.times { |i| i.even? ? create_post(title: "Many #{i}") : create_page(title: "Many page #{i}") }
    assert_equal few.size, queries_for_request.call.size, "more rows"

    with_locales(%w[en de es fr it], default: "en")
    get "/cs-studio/translations"
    assert_equal few.size, queries_for_request.call.size, "more languages"
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
