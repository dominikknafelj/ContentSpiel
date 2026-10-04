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

  test "lists missing and outdated pages, posts and images for one language, grouped, linking to the editor there" do
    missing_page = create_page(title: "Untranslated page")
    outdated_page = complete_page("Changed page")
    assert Pages::Save.call(outdated_page, translations: { "en" => { title: "Changed page!" } }).ok?
    missing_post = create_post(title: "Untranslated post")
    stale_post = outdated_post("Stale post")
    image = image_with_alt("A cat")

    get "/cs-studio/translations", params: { locale: "de" }

    assert_response :success
    assert_select "h1", text: "Translations"
    assert_select "section#translations-pages" do
      assert_select "h2", text: "Pages"
      assert_select "##{row_id("page", missing_page)} a[href='/cs-studio/pages/#{missing_page.id}?locale=de']", text: "Untranslated page"
      assert_select "##{row_id("page", missing_page)} [data-translation-state='missing']"
      assert_select "##{row_id("page", outdated_page)} [data-translation-state='outdated']"
    end
    assert_select "section#translations-posts" do
      assert_select "h2", text: "Posts"
      assert_select "##{row_id("post", missing_post)} a[href='/cs-studio/posts/#{missing_post.id}?locale=de']"
      assert_select "##{row_id("post", missing_post)} [data-translation-state='missing']"
      assert_select "##{row_id("post", stale_post)} a[href='/cs-studio/posts/#{stale_post.id}?locale=de']"
      assert_select "##{row_id("post", stale_post)} [data-translation-state='outdated']"
    end
    assert_select "section#translations-media" do
      assert_select "h2", text: "Images"
      assert_select "##{row_id("media", image)} a[href='/cs-studio/media/#{image.id}?locale=de']"
      assert_select "##{row_id("media", image)} [data-translation-state='missing']"
    end
    # The tabs list the target languages only, the chosen one current.
    assert_select "nav[aria-label='Target languages'] a", count: 2
    assert_select "nav[aria-label='Target languages'] a[aria-current='page']", text: /Deutsch/
    assert_select "nav[aria-label='Target languages'] a", text: /English/, count: 0
  end

  test "excludes complete and trashed items" do
    done = complete_post("Done post")
    trashed = create_post(title: "Trashed post")
    assert Trash::Move.call(trashed).ok?
    done_page = complete_page("Done page")
    done_image = image_with_alt("A dog", "de" => { alt: "Ein Hund" })
    no_alt = create_media_asset
    trashed_image = image_with_alt("A bird")
    assert Trash::Move.call(trashed_image).ok?

    get "/cs-studio/translations", params: { locale: "de" }

    assert_response :success
    assert_select "##{row_id("post", done)}", count: 0
    assert_select "##{row_id("post", trashed)}", count: 0
    assert_select "##{row_id("page", done_page)}", count: 0
    assert_select "##{row_id("media", done_image)}", count: 0
    assert_select "##{row_id("media", no_alt)}", count: 0
    assert_select "##{row_id("media", trashed_image)}", count: 0
  end

  test "a section is left out when nothing of its type needs work, and an empty language says so" do
    Page.find_each { |page| assert Pages::Save.call(page, translations: { "de" => { title: "Startseite #{page.id}" } }).ok? }

    get "/cs-studio/translations", params: { locale: "de" }

    assert_response :success
    assert_select "section#translations-pages", count: 0
    assert_select "section#translations-posts", count: 0
    assert_select "section#translations-media", count: 0
    assert_select "h3", text: /Everything is translated into Deutsch/
  end

  test "filters by type" do
    page = create_page(title: "Untranslated page")
    post_record = create_post(title: "Untranslated post")

    get "/cs-studio/translations", params: { locale: "de", type: "post" }

    assert_response :success
    assert_select "##{row_id("post", post_record)}"
    assert_select "##{row_id("page", page)}", count: 0
    assert_select "nav[aria-label='Filter by type'] a[aria-current='page']", text: "Posts"
  end

  test "is read-scoped: an author whose reads stop at their own posts doesn't see anyone else's" do
    access_control_grants(:author_posts_read).update!(scope: { "own" => true })
    access_control_grants(:author_posts_create).update!(scope: { "own" => true })
    own = create_post(title: "Own post")
    own.update_column(:author_id, users(:author).id)
    other = create_post(title: "Other post")
    other.update_column(:author_id, users(:two).id)
    sign_out
    sign_in_as(users(:author))

    get "/cs-studio/translations", params: { locale: "de" }

    assert_response :success
    assert_select "##{row_id("post", own)}"
    assert_select "##{row_id("post", other)}", count: 0
    assert_not_includes response.body, "Other post"
  end

  test "images are listed only for someone holding media.upload" do
    image = image_with_alt("A cat")
    sign_out
    sign_in_as(users(:reader))

    get "/cs-studio/translations", params: { locale: "de" }

    assert_response :success
    assert_select "##{row_id("media", image)}", count: 0
    assert_select "nav[aria-label='Filter by type'] a", text: "Images", count: 0
  end

  test "pages through results, about 50 per page" do
    posts = Array.new(51) { |index| create_post(title: "Post #{index}") }

    get "/cs-studio/translations", params: { locale: "de", type: "post" }

    assert_response :success
    assert_select "section#translations-posts li[id^='translation-item-post-']", count: Admin::TranslationsController::PER_PAGE
    assert_select "a", text: "Previous", count: 0
    assert_select "a[href*='page=2']", text: "Next"

    get "/cs-studio/translations", params: { locale: "de", type: "post", page: 2 }

    assert_response :success
    assert_select "section#translations-posts li[id^='translation-item-post-']", count: 1
    assert_select "##{row_id("post", posts.last)}"
    assert_select "a", text: "Next", count: 0
    assert_select "a", text: "Previous"
  end

  test "junk and out-of-range page numbers never error" do
    create_post(title: "One post")

    %w[0 abc -1].each do |junk|
      get "/cs-studio/translations", params: { locale: "de", page: junk }
      assert_response :success
    end
    get "/cs-studio/translations", params: { locale: "de", page: 9999 }
    assert_response :success
    assert_select "a", text: "Back to page 1"
  end

  test "an unknown, default or absent locale redirects to the first target language" do
    [ { locale: "en" }, { locale: "xx" }, {} ].each do |params|
      get "/cs-studio/translations", params: params.merge(type: "post")

      assert_redirected_to "/cs-studio/translations?locale=de&type=post", "for #{params.inspect}"
    end
  end

  test "with one language enabled there is nothing to translate into" do
    with_locales(%w[en], default: "en")

    get "/cs-studio/translations"

    assert_redirected_to "/cs-studio"
  end

  test "needs pages.read or posts.read" do
    sign_out
    sign_in_as(users(:editor_branch))

    get "/cs-studio/translations", params: { locale: "de" }

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
