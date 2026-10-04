require "application_system_test_case"

# The translation helpers end to end, in a real browser (translation
# helpers spec §4-§6): the editor's Translate / Use / "Translate empty
# fields" / "Use all" (`admin--translate`), which only a browser can run --
# the request is a `fetch`, Use fills the input and lets the form's own
# `admin--autosave` save it, and a rich-text Use goes through the Tiptap
# editor (`admin--rich-text#applySuggestion`) -- plus the outdated note,
# the Translations overview and the translated site tagline.
#
# The AI provider is a stub registered for these tests as `test/stub` (the
# app server runs in this process, so it sees the same registry) and never
# reaches the network: it answers `"[de] " + text`, and raises for any
# request containing "boom" -- how a provider error during a bulk
# translation is staged. Teardown re-runs the `to_prepare` registrations,
# which reset the provider registry (and, after `with_test_types`, the
# block types) to their built-ins.
class Admin::TranslationsSystemTest < ApplicationSystemTestCase
  include TestTypes

  class StubProvider
    # Seconds to wait before answering: how a slow provider is staged (Cancel
    # while a request is out).
    cattr_accessor :delay, default: 0

    def initialize(api_key:, model:); end

    def translate(texts:, from:, to:, format:)
      sleep delay if delay.positive?
      raise AI::Error, "The AI provider is unavailable." if texts.any? { |text| text.to_s.downcase.include?("boom") }

      texts.map { |text| "[#{to}] #{text}" }
    end
  end

  setup do
    StubProvider.delay = 0
    site_settings(:default).update!(setup_completed_at: Time.current)
    with_locales(%w[en de es], default: "en")
    AI::Providers.register("test/stub", StubProvider)
    site_settings(:default).update!(ai_provider: "test/stub", ai_api_key: "sk-test")
    sign_in_via_form(users(:one))
  end

  teardown { Rails.application.reloader.prepare! }

  def paragraph(text) = { "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => text } ] } ] }

  # A scripted click on the button labelled `label` inside `scope` -- the
  # `press` workaround (see `ApplicationSystemTestCase#press`), scoped,
  # since every translated field has its own "Translate" button.
  def press_within(scope, label)
    within(scope) { find(:link_or_button, label, exact: true).execute_script("this.click()") }
  end

  # A plain suggestion's text is the value of an editable textarea, which
  # `text:` doesn't see.
  def assert_suggestion(box_id, text)
    assert_selector "##{box_id} textarea[data-translate-suggestion-text]", visible: true
    assert_equal text, find("##{box_id} textarea[data-translate-suggestion-text]").value
  end

  def slot(field) = "[data-translate-slot='#{field}']"

  test "Translate, then Use, fills the German title and autosaves it" do
    post = create_post(title: "Hello")

    visit "/cs-studio/posts/#{post.id}?locale=de"
    await_admin_controllers

    press_within slot("title"), "Translate"
    assert_suggestion "translation-suggestion-post-title", "[de] Hello"
    assert_nil post.reload.title(locale: "de", fallback: false), "Translate alone saves nothing"

    press_within "#translation-suggestion-post-title", "Use"

    assert_selector "#post-save-status", text: /\A(● )?SAVED( TO SITE)? \d{2}:\d{2}\z/, wait: 5
    assert_equal "[de] Hello", find_field(id: "post-title").value
    assert_no_selector "#translation-suggestion-post-title [data-translation-suggestion]"
    post.reload
    assert_equal "[de] Hello", post.title(locale: "de", fallback: false)
    assert_equal :current, post.translation_state("title", "de")
  end

  test "an edited suggestion is what Use applies, and editing it saves nothing by itself" do
    post = create_post(title: "Hello")

    visit "/cs-studio/posts/#{post.id}?locale=de"
    await_admin_controllers

    press_within slot("title"), "Translate"
    suggestion = find("#translation-suggestion-post-title textarea[data-translate-suggestion-text]")
    assert_equal "[de] Hello", suggestion.value
    assert_selector "#translation-suggestion-post-title", text: /SUGGESTED TRANSLATION · EDIT BEFORE USING\s+claude-sonnet-5/
    # Under the field's own input, in its column -- not in the original's panel.
    assert_selector "[data-field-name='title'] #translation-suggestion-post-title"
    assert_no_selector "#{slot("title")} #translation-suggestion-post-title"

    suggestion.fill_in with: "Edited by hand"
    # Past the autosave debounce (1 s): had the textarea's input or focusout
    # reached the form, a save would have run by now.
    sleep 1.5
    assert_no_selector "#post-save-status", text: /SAVED|SAVING/, wait: 0
    assert_nil post.reload.title(locale: "de", fallback: false), "editing a suggestion is not editing the field"
    assert_equal "", find_field(id: "post-title").value

    press_within "#translation-suggestion-post-title", "Use"

    assert_selector "#post-save-status", text: /\A(● )?SAVED( TO SITE)? \d{2}:\d{2}\z/, wait: 5
    assert_equal "Edited by hand", find_field(id: "post-title").value
    assert_equal "Edited by hand", post.reload.title(locale: "de", fallback: false)

    visit "/cs-studio/posts/#{post.id}?locale=de"
    assert_equal "Edited by hand", find_field(id: "post-title").value
  end

  test "Translate, then Use, loads a rich-text body into the editor and saves the document" do
    post = create_post(title: "Hello")
    assert Posts::Save.call(post, translations: { "en" => { body: paragraph("Body text") } }).ok?

    visit "/cs-studio/posts/#{post.id}?locale=de"
    await_admin_controllers

    press_within slot("body"), "Translate"
    assert_selector "#translation-suggestion-post-body-json", text: "[de] Body text"

    press_within "#translation-suggestion-post-body-json", "Use"

    assert_selector "#post-save-status", text: /\A(● )?SAVED( TO SITE)? \d{2}:\d{2}\z/, wait: 5
    post.reload
    assert_equal paragraph("[de] Body text"), post.body(locale: "de").to_h
    assert_equal :current, post.translation_state("body", "de")
  end

  test "Translate empty fields, then Use all, fills the page's fields and its block's" do
    with_test_types do
      page_record = create_page(title: "About")
      assert Pages::Save.call(page_record, translations: { "en" => { subtitle: "Who we are" } }).ok?
      block = ContentBlocks::Save.call(ContentBlock.new(owner: page_record), attributes: { block_type: "test/quote" },
        translations: { "en" => { settings: { "text" => "To be" } } }).record

      visit "/cs-studio/pages/#{page_record.id}?locale=de"
      await_admin_controllers

      press "Suggest translations for 3 empty fields"
      assert_text "3 suggestions ready"
      assert_suggestion "translation-suggestion-page-title", "[de] About"
      assert_suggestion "translation-suggestion-page-subtitle", "[de] Who we are"
      assert_suggestion "translation-suggestion-block-#{block.id}-text", "[de] To be"

      press "Use all"

      assert_selector "#page-save-status", text: /\A(● )?SAVED( TO SITE)? \d{2}:\d{2}\z/, wait: 5
      assert_selector "#block-#{block.id}-save-status", text: /\A(● )?SAVED( TO SITE)? \d{2}:\d{2}\z/, wait: 5
      page_record.reload
      assert_equal "[de] About", page_record.title(locale: "de", fallback: false)
      assert_equal "[de] Who we are", page_record.subtitle(locale: "de", fallback: false)
      assert_equal "[de] To be", block.reload.translated_settings.dig("de", "text")

      # "Use all" fires the page form's and the block's saves on the same tick.
      # Sent together they would carry the same page base, and the second
      # would leave the page form holding a base nobody else made stale: its
      # next save would be refused ("changed elsewhere") with no one else
      # involved. The page-level queue (`autosave/queue.js`) prevents that.
      fill_in id: "page-subtitle", with: "[de] Typed after Use all"
      assert_eventually { page_record.reload.subtitle(locale: "de", fallback: false) == "[de] Typed after Use all" }
      assert_no_text "CHANGED ELSEWHERE"
    end
  end

  test "Use all across two blocks leaves the page settings form able to save" do
    with_test_types do
      page_record = create_page(title: "About")
      blocks = 2.times.map do |i|
        ContentBlocks::Save.call(ContentBlock.new(owner: page_record), attributes: { block_type: "test/quote" },
          translations: { "en" => { settings: { "text" => "Line #{i}" } } }).record
      end

      visit "/cs-studio/pages/#{page_record.id}?locale=de"
      await_admin_controllers

      press "Suggest translations for 3 empty fields"
      assert_text "3 suggestions ready"
      press "Use all"
      blocks.each { |block| assert_selector "#block-#{block.id}-save-status", text: /\A(● )?SAVED( TO SITE)? \d{2}:\d{2}\z/, wait: 5 }

      fill_in id: "page-subtitle", with: "Typed after Use all"
      assert_eventually { page_record.reload.subtitle(locale: "de", fallback: false) == "Typed after Use all" }
      assert_no_text "CHANGED ELSEWHERE"
    end
  end

  test "a provider error during Translate empty fields shows under its fields and doesn't stop the others" do
    with_test_types do
      page_record = create_page(title: "Boom")
      block = ContentBlocks::Save.call(ContentBlock.new(owner: page_record), attributes: { block_type: "test/quote" },
        translations: { "en" => { settings: { "text" => "To be" } } }).record

      visit "/cs-studio/pages/#{page_record.id}?locale=de"
      await_admin_controllers

      # The page's own fields are one request (it fails), the block's
      # another (it works): one record per request.
      press "Suggest translations for 2 empty fields"
      assert_selector "#translation-suggestion-page-title [role='alert']", text: "The AI provider is unavailable."
      assert_suggestion "translation-suggestion-block-#{block.id}-text", "[de] To be"
      # The error box is no suggestion: only the block's counts.
      assert_text "1 suggestion ready"

      press_within "#translation-suggestion-page-title", "Dismiss"
      assert_no_selector "#translation-suggestion-page-title [role='alert']"

      press "Use all"
      assert_selector "#block-#{block.id}-save-status", text: /\A(● )?SAVED( TO SITE)? \d{2}:\d{2}\z/, wait: 5
      assert_equal "[de] To be", block.reload.translated_settings.dig("de", "text")
      assert_nil page_record.reload.title(locale: "de", fallback: false)
    end
  end

  def post_with_excerpt
    post = create_post(title: "Hello")
    assert Posts::Save.call(post, translations: { "en" => { excerpt: "A summary" } }).ok?
    post
  end

  test "the header counts the empty fields, shows a pending box per field, then the ready line; an edited suggestion is what Use all applies" do
    post = post_with_excerpt
    StubProvider.delay = 1.5

    visit "/cs-studio/posts/#{post.id}?locale=de"
    await_admin_controllers
    assert_button "Suggest translations for 2 empty fields"

    press "Suggest translations for 2 empty fields"
    assert_text "Suggesting 1 of 2 fields"
    assert_selector "#translation-suggestion-post-title [data-translation-pending]", text: /\d+s/
    assert_selector "#translation-suggestion-post-excerpt [data-translation-pending]"
    assert_text "2 suggestions ready", wait: 8
    assert_no_selector "[data-translation-pending]"
    assert_suggestion "translation-suggestion-post-title", "[de] Hello"
    assert_suggestion "translation-suggestion-post-excerpt", "[de] A summary"
    assert_nil post.reload.title(locale: "de", fallback: false), "suggesting saves nothing"

    find("#translation-suggestion-post-excerpt textarea[data-translate-suggestion-text]").fill_in with: "Edited summary"
    press "Use all"

    assert_selector "#post-save-status", text: /\A(● )?SAVED( TO SITE)? \d{2}:\d{2}\z/, wait: 5
    assert_equal "[de] Hello", find_field(id: "post-title").value
    assert_equal "Edited summary", find_field(id: "post-excerpt").value
    assert_no_selector "[data-translation-suggestion]"
    # Nothing is empty any more: the header has nothing left to offer.
    assert_no_button "Suggest translations for"
    assert_no_text "suggestions ready"

    visit "/cs-studio/posts/#{post.id}?locale=de"
    assert_equal "[de] Hello", find_field(id: "post-title").value
    assert_equal "Edited summary", find_field(id: "post-excerpt").value
    post.reload
    assert_equal "Edited summary", post.excerpt(locale: "de", fallback: false)
  end

  test "Discard all removes every suggestion and saves nothing" do
    post = post_with_excerpt

    visit "/cs-studio/posts/#{post.id}?locale=de"
    await_admin_controllers
    press "Suggest translations for 2 empty fields"
    assert_text "2 suggestions ready"

    press "Discard all"

    assert_no_selector "[data-translation-suggestion]"
    assert_no_text "suggestions ready"
    assert_button "Suggest translations for 2 empty fields"
    sleep 1.5
    assert_no_selector "#post-save-status", text: /SAVED|SAVING/, wait: 0
    post.reload
    assert_nil post.title(locale: "de", fallback: false)
    assert_nil post.excerpt(locale: "de", fallback: false)
  end

  test "Cancel in the header removes the pending boxes, and the late answer never appears" do
    post = post_with_excerpt
    StubProvider.delay = 2

    visit "/cs-studio/posts/#{post.id}?locale=de"
    await_admin_controllers
    press "Suggest translations for 2 empty fields"
    assert_selector "#translation-suggestion-post-title [data-translation-pending]"

    within("[data-admin--translate-target='running']") { click_on "Cancel" }

    assert_no_selector "[data-translation-pending]"
    assert_button "Suggest translations for 2 empty fields"
    sleep 3
    assert_no_selector "[data-translation-suggestion]"
    assert_nil post.reload.title(locale: "de", fallback: false)
  end

  test "Cancel on one pending box stops that request only" do
    post = post_with_excerpt
    StubProvider.delay = 2

    visit "/cs-studio/posts/#{post.id}?locale=de"
    await_admin_controllers
    press_within slot("title"), "Translate"
    assert_selector "#translation-suggestion-post-title [data-translation-pending]"

    press_within "#translation-suggestion-post-title [data-translation-pending]", "Cancel"

    assert_no_selector "[data-translation-pending]"
    sleep 3
    assert_no_selector "#translation-suggestion-post-title [data-translation-suggestion]"
    assert_nil post.reload.title(locale: "de", fallback: false)
  end

  # The layout's template carries the seconds a request may take; a test
  # shortens it so the 25 second state needs one second, not 25.
  def shorten_pending_timeout(seconds)
    page.execute_script(<<~JS)
      document.getElementById("translation-pending-template").content.firstElementChild.dataset.pendingTimeoutSeconds = "#{seconds}"
    JS
  end

  test "a request that takes too long turns into the timeout box; its late answer is ignored; Try again asks anew" do
    post = post_with_excerpt
    StubProvider.delay = 2.5

    visit "/cs-studio/posts/#{post.id}?locale=de"
    await_admin_controllers
    shorten_pending_timeout(1)
    press_within slot("title"), "Translate"

    assert_selector "#translation-suggestion-post-title", text: "No suggestion after 25 seconds.", wait: 4
    # The server answers after 2.5 s: the box must stay as it is.
    sleep 3
    assert_selector "#translation-suggestion-post-title", text: "No suggestion after 25 seconds."
    assert_no_selector "#translation-suggestion-post-title [data-translation-suggestion]"

    StubProvider.delay = 0
    press_within "#translation-suggestion-post-title", "Try again"

    assert_suggestion "translation-suggestion-post-title", "[de] Hello"
    assert_no_selector "[data-translation-pending]"
  end

  test "switching language mid-run drops the request: nothing lands on the new page" do
    post = post_with_excerpt
    StubProvider.delay = 2

    visit "/cs-studio/posts/#{post.id}?locale=de"
    await_admin_controllers
    press "Suggest translations for 2 empty fields"
    assert_selector "#translation-suggestion-post-title [data-translation-pending]"

    click_on "Español"
    assert_current_path(/locale=es/)
    await_admin_controllers
    sleep 3
    assert_no_selector "[data-translation-suggestion]"
    assert_no_selector "[data-translation-pending]"
    assert_equal "", find_field(id: "post-title").value
    assert_nil post.reload.title(locale: "es", fallback: false)
  end

  test "the header announces progress and readiness in one live region, and focus follows Use and Discard" do
    post = post_with_excerpt
    StubProvider.delay = 1

    visit "/cs-studio/posts/#{post.id}?locale=de"
    await_admin_controllers
    press "Suggest translations for 2 empty fields"
    assert_selector "[role='status'][aria-live='polite'][data-admin--translate-target='status']", text: /Suggesting 1 of 2 fields/, visible: :all
    assert_selector "[data-admin--translate-target='status']", text: "2 suggestions ready", visible: :all, wait: 8

    # Focus inside the box moves to the field after Use, to Translate-ish after Discard.
    find("#translation-suggestion-post-title [data-translate-use]").execute_script("this.focus(); this.click()")
    assert_equal "post-title", page.evaluate_script("document.activeElement.id")
    find("#translation-suggestion-post-excerpt button", text: "Discard").execute_script("this.focus(); this.click()")
    assert_no_selector "#translation-suggestion-post-excerpt [data-translation-suggestion]"
    assert page.evaluate_script("document.activeElement.closest('[data-translate-slot]') !== null"), "focus lands on the field's Translate button"
  end

  test "Suggest update on an outdated field shows the full new text and the current translation, and Use replaces the value" do
    post = create_post(title: "About us")
    assert Posts::Save.call(post, translations: { "de" => { title: "Über uns" } }).ok?
    assert Posts::Save.call(post, translations: { "en" => { title: "About our team" } }).ok?

    visit "/cs-studio/posts/#{post.id}?locale=de"
    await_admin_controllers
    assert_no_selector "#{slot("title")} button", text: "Translate"

    press_within "[data-original-for='title']", "Suggest update"

    assert_suggestion "translation-suggestion-post-title", "[de] About our team"
    assert_selector "#translation-suggestion-post-title [data-suggestion-current]", text: "Current: Über uns"
    assert_equal "Über uns", find_field(id: "post-title").value, "a suggestion is not applied until Use"

    press_within "#translation-suggestion-post-title", "Use"

    assert_selector "#post-save-status", text: /\A(● )?SAVED( TO SITE)? \d{2}:\d{2}\z/, wait: 5
    assert_equal "[de] About our team", post.reload.title(locale: "de", fallback: false)
    assert_equal :current, post.translation_state("title", "de")
  end

  test "an answer that isn't a stream shows a generic error the editor can dismiss" do
    post = create_post(title: "Hello")

    visit "/cs-studio/posts/#{post.id}?locale=de"
    await_admin_controllers
    # Trashed after the page loaded: the request is now a 404 page, not a
    # stream, so the box is filled by `admin--translate` itself.
    assert Trash::Move.call(post).ok?

    press_within slot("title"), "Translate"
    assert_selector "#translation-suggestion-post-title [role='alert']", text: "Couldn't get a suggestion"
    dismiss = find("#translation-suggestion-post-title button", text: "Dismiss")
    assert_equal "button", dismiss[:type], "never a submit -- the box sits inside the autosave form"

    press_within "#translation-suggestion-post-title", "Dismiss"
    assert_no_selector "#translation-suggestion-post-title [data-translation-suggestion]"
  end

  test "editing the English title flags the German one, and Mark as up to date clears it" do
    post = create_post(title: "Hello")
    assert Posts::Save.call(post, translations: { "de" => { title: "Hallo" } }).ok?

    visit "/cs-studio/posts/#{post.id}"
    await_admin_controllers
    fill_in "Title", with: "Hello there"
    assert_selector "#post-save-status", text: /\A(● )?SAVED( TO SITE)? \d{2}:\d{2}\z/, wait: 5
    assert_equal :outdated, post.reload.translation_state("title", "de")

    visit "/cs-studio/posts/#{post.id}?locale=de"
    await_admin_controllers
    assert_selector "[data-original-for='title'] ins", text: "there"

    click_on "Still correct — mark up to date"

    assert_no_selector "[data-original-for='title'] ins", wait: 5
    assert_equal :current, post.reload.translation_state("title", "de")
    assert_equal "Hallo", post.title(locale: "de", fallback: false)
  end

  test "the matrix lists a post missing in German and links into its German editor" do
    post = create_post(title: "Only in English")

    visit "/cs-studio/translations"

    assert_text "Posts"
    click_on "Only in English"

    assert_current_path "/cs-studio/posts/#{post.id}?locale=de"
    assert_selector "[data-original-for='title']", text: "Only in English"
  end

  test "the matrix lists an outdated post first; its DE chip opens the outdated card; marking it up to date clears the row and raises the card" do
    missing = create_post(title: "Never translated")
    missing.update_columns(updated_at: 1.minute.from_now)
    stale = create_post(title: "Hello")
    assert Posts::Save.call(stale, translations: { "de" => { title: "Hallo" }, "es" => { title: "Hola" } }).ok?
    assert Posts::Save.call(stale, translations: { "en" => { title: "Hello there" } }).ok?
    Translations::StateIndex.rebuild_all
    stale_row = "#translation-item-post-#{stale.id}"

    visit "/cs-studio/translations"

    rows = all("tbody tr[id^='translation-item-post-']").map { |row| row[:id] }
    assert_equal [ stale_row.delete("#"), "translation-item-post-#{missing.id}" ], rows
    assert_selector "#{stale_row} td a", text: "Review changes →"
    before = find("[data-translation-summary] [data-locale=de] [role=progressbar]")["aria-valuenow"].to_i

    find("#{stale_row} a[aria-label$='Deutsch, outdated']").click
    assert_current_path "/cs-studio/posts/#{stale.id}?locale=de"
    await_admin_controllers
    assert_selector "[data-original-for='title'] ins", text: "there"
    click_on "Still correct — mark up to date"
    assert_no_selector "[data-original-for='title'] ins", wait: 5

    visit "/cs-studio/posts/#{stale.id}?locale=es"
    await_admin_controllers
    click_on "Still correct — mark up to date"
    assert_no_selector "[data-original-for='title'] ins", wait: 5

    visit "/cs-studio/translations"
    assert_no_selector stale_row
    assert_selector "#translation-item-post-#{missing.id}"
    after = find("[data-translation-summary] [data-locale=de] [role=progressbar]")["aria-valuenow"].to_i
    assert_operator after, :>, before
  end

  test "Settings in German show the tagline's original, and the German tagline reaches /de" do
    root_page
    Mobility.with_locale(:en) { site_settings(:default).update!(title: "Dana's Notes", tagline: "Things I learned") }

    visit "/cs-studio/settings?locale=de"
    await_admin_controllers
    assert_selector "[data-original-for='tagline']", text: "Things I learned"

    fill_in "settings-tagline", with: "Was ich gelernt habe"
    assert_selector "#settings-save-status", text: /\A(● )?SAVED( TO SITE)? \d{2}:\d{2}\z/, wait: 5
    assert_equal "Things I learned", site_settings(:default).reload.tagline(locale: "en")

    # The homepage eyebrow is uppercased by CSS, hence case-insensitive.
    visit "/de"
    assert_text(/Was ich gelernt habe/i)
    assert_no_text(/Things I learned/i)
  end
end
