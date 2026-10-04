require "test_helper"

# Translation status in the editors (translation helpers spec §4, Task 3):
# an outdated field says so beside its original, with a "Mark as up to
# date" button posting to `Admin::TranslationConfirmationsController`, and
# the language switcher marks the language as outdated.
class Admin::TranslationStatusTest < ActionDispatch::IntegrationTest
  include TestTypes

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    with_locales(%w[en de es], default: "en")
    sign_in_as(users(:one))
  end

  def paragraph(text) = { "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => text } ] } ] }

  def outdated_post
    record = create_post(title: "Hello")
    assert Posts::Save.call(record, translations: { "de" => { title: "Hallo" } }).ok?
    assert Posts::Save.call(record, translations: { "en" => { title: "Hello!" } }).ok?
    record.reload
  end

  def note_id(type, record, field) = "reference-card-#{type}-#{record.id}-#{field}"

  def confirm_params(record, field, locale = "de")
    { record_type: record.class.name, record_id: record.id, field: field, locale: locale }
  end

  test "an outdated German title shows the note, the button and the switcher marker" do
    record = outdated_post

    get "/cs-studio/posts/#{record.id}", params: { locale: "de" }

    assert_response :success
    assert_select "##{note_id("post", record, "title")}[data-translation-state='outdated']"
    # The title was translated after sources kept their text, so the card diffs.
    assert_select "##{note_id("post", record, "title")} ins", text: "Hello!"
    assert_select "##{note_id("post", record, "title")} del", text: "Hello"
    # The button belongs to the layout's one confirm form (outside every
    # autosave form -- forms can't nest), and names its record in the
    # `formaction`.
    assert_select "form#translation-confirm-form[action='/cs-studio/translations/confirm'][method='post']"
    assert_select "##{note_id("post", record, "title")} button[form='translation-confirm-form']", text: "Still correct — mark up to date" do |buttons|
      action = buttons.first["formaction"]
      assert_equal "/cs-studio/translations/confirm", URI(action).path
      assert_equal confirm_params(record, "title").transform_keys(&:to_s).transform_values(&:to_s), Rack::Utils.parse_query(URI(action).query)
    end
    assert_select "#language-switcher-outdated-de[title='Original changed']"
    assert_select "#language-switcher-outdated-es", count: 0
    # A field translated in step reads nothing.
    assert_select "##{note_id("post", record, "excerpt")}", count: 0
  end

  test "the default language never shows the note" do
    record = outdated_post

    get "/cs-studio/posts/#{record.id}"

    assert_response :success
    assert_select "[data-translation-state='outdated']", count: 0
  end

  test "posting the confirm form clears the note and the marker" do
    record = outdated_post

    post "/cs-studio/translations/confirm", params: confirm_params(record, "title"),
      headers: { "HTTP_REFERER" => "http://www.example.com/cs-studio/posts/#{record.id}?locale=de" }

    assert_redirected_to "http://www.example.com/cs-studio/posts/#{record.id}?locale=de"
    assert_equal :current, record.reload.translation_state("title", "de")
    follow_redirect!
    assert_select "##{note_id("post", record, "title")}[data-translation-state='current']"
    assert_select "##{note_id("post", record, "title")} del", count: 0
    assert_select "#language-switcher-outdated-de", count: 0
    assert_includes response.body, "Marked as up to date"
  end

  test "a Turbo confirm removes the note, and the marker once nothing else is outdated" do
    record = outdated_post
    assert Posts::Save.call(record, translations: { "en" => { excerpt: "Short" } }).ok?
    assert Posts::Save.call(record, translations: { "de" => { excerpt: "Kurz" } }).ok?
    assert Posts::Save.call(record, translations: { "en" => { excerpt: "Shorter" } }).ok?
    assert_equal :outdated, record.reload.translation_state("excerpt", "de")

    post "/cs-studio/translations/confirm", params: confirm_params(record, "title"), as: :turbo_stream

    assert_response :success
    assert_includes response.body, %(<turbo-stream action="replace" target="#{note_id("post", record, "title")}">)
    assert_includes response.body, %(data-translation-state="current")
    assert_not_includes response.body, "<del"
    assert_not_includes response.body, "language-switcher-outdated-de"

    post "/cs-studio/translations/confirm", params: confirm_params(record, "excerpt"), as: :turbo_stream

    assert_includes response.body, %(<turbo-stream action="remove" target="language-switcher-outdated-de">)
  end

  test "the page form, its block cards and the media detail show the note too" do
    with_test_types do
      page = create_page(title: "About", translations: { "de" => { title: "Über" } })
      assert Pages::Save.call(page, translations: { "en" => { title: "About us" } }).ok?
      block = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "test/quote" },
        translations: { "en" => { settings: { "text" => "To be" } }, "de" => { settings: { "text" => "Sein" } } }).record
      assert ContentBlocks::Save.call(block, translations: { "en" => { settings: { "text" => "Not to be" } } }).ok?

      get "/cs-studio/pages/#{page.id}", params: { locale: "de" }

      assert_response :success
      assert_select "##{note_id("page", page, "title")} button", text: "Still correct — mark up to date"
      assert_select "##{note_id("content-block", block, "text")} button", text: "Still correct — mark up to date"
      assert_select "#language-switcher-outdated-de"
    end

    asset = create_media_asset
    assert Media::Save.call(asset, translations: { "en" => { alt: "Sand" }, "de" => { alt: "Sand (de)" } }).ok?
    assert Media::Save.call(asset, translations: { "en" => { alt: "Sand dunes" } }).ok?

    get "/cs-studio/media/#{asset.id}", params: { locale: "de" }

    assert_response :success
    assert_select "[data-original-for='alt'] p", text: "Sand dunes"
    assert_select "##{note_id("media-asset", asset, "alt")} button", text: "Still correct — mark up to date"
    assert_select "#language-switcher-outdated-de"
    # Ruling: alt present in English, blank in Spanish -- missing there.
    assert_select "nav[aria-label='Languages'] [title='Missing required fields']", count: 1
  end

  test "a language both missing and outdated shows both markers" do
    with_test_types do
      page = create_page(title: "About", translations: { "de" => { title: "Über" } })
      assert Pages::Save.call(page, translations: { "en" => { title: "About us" } }).ok?
      assert ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "test/quote" },
        translations: { "en" => { settings: { "text" => "To be" } } }).ok?

      get "/cs-studio/pages/#{page.id}", params: { locale: "de" }

      assert_response :success
      assert_select "#language-switcher-outdated-de"
      assert_select "nav[aria-label='Languages'] [title='Missing required fields']", minimum: 1
    end
  end

  test "a view-only reader sees the diff but no button" do
    record = outdated_post
    sign_in_as(users(:reader))

    get "/cs-studio/posts/#{record.id}", params: { locale: "de" }

    assert_response :success
    assert_select "##{note_id("post", record, "title")} ins", text: "Hello!"
    assert_select "button", text: "Still correct — mark up to date", count: 0
  end

  test "a record outside the read scope is a 404, and so is a trashed one or an unknown type" do
    record = outdated_post
    sign_in_as(users(:editor_branch))

    post "/cs-studio/translations/confirm", params: confirm_params(record, "title")
    assert_response :not_found

    sign_in_as(users(:one))
    page = create_page(title: "Gone")
    assert Trash::Move.call(page).ok?
    post "/cs-studio/translations/confirm", params: confirm_params(page, "title")
    assert_response :not_found

    post "/cs-studio/translations/confirm", params: { record_type: "User", record_id: users(:one).id, field: "email_address", locale: "de" }
    assert_response :not_found
    assert_equal :outdated, record.reload.translation_state("title", "de")
  end

  test "a refused write is a 403" do
    record = outdated_post
    sign_in_as(users(:reader))

    post "/cs-studio/translations/confirm", params: confirm_params(record, "title")

    assert_response :forbidden
    assert_equal :outdated, record.reload.translation_state("title", "de")
  end

  test "a field with nothing to confirm is refused without a write" do
    record = outdated_post

    post "/cs-studio/translations/confirm", params: confirm_params(record, "slug"),
      headers: { "HTTP_REFERER" => "http://www.example.com/cs-studio/posts/#{record.id}?locale=de" }

    assert_redirected_to "http://www.example.com/cs-studio/posts/#{record.id}?locale=de"
    assert_equal "Nothing to confirm", flash[:alert]
    assert_not Audit::Event.exists?(action: "post.translation_confirmed")
  end
end
