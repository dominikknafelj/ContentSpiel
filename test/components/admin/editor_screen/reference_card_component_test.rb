require "test_helper"

class Admin::EditorScreen::ReferenceCardComponentTest < ViewComponent::TestCase
  def render_card(**options)
    render_inline(Admin::EditorScreen::ReferenceCardComponent.new(field: "title", locale: "de", original: "About us", **options))
  end

  test "shows the primary language's own name and the original beside its state" do
    render_card(state: :current)

    assert_selector "div.admin-reference-card[data-original-for='title'][data-translation-state='current']"
    assert_selector ".admin-reference-card", text: Locales.name(Locales.default, native: true)
    assert_selector ".admin-reference-card p", text: "About us"
  end

  test "carries each state on the root" do
    %i[outdated unknown missing].each do |state|
      render_card(state: state)
      assert_selector ".admin-reference-card[data-translation-state='#{state}']"
    end
  end

  test "the summary is a disclosure: the triangle, the language, and the change time at the far end" do
    post = create_post(title: "Hello")
    render_inline Admin::EditorScreen::ReferenceCardComponent.new(field: "title", locale: "de", original: "Hello", record: post)

    assert_selector "summary.admin-disclosure > span:first-child", text: Locales.name(Locales.default, native: true)
    assert_no_selector "summary.justify-between"
  end

  test "a rich original is rendered HTML, scrubbed" do
    document = RichText::Document.new(
      "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "Hello <script>alert(1)</script>", "marks" => [ { "type" => "bold" } ] } ] } ]
    )

    render_card(field: "body", original: document, kind: :rich)

    assert_selector "[data-original-for='body'] strong", text: "Hello"
    assert_no_selector "script"
  end

  # Records built through the real services, so the stored source (text, time,
  # primary language) is exactly what production writes.
  def outdated_post(title: "A spare room", changed: "A small room")
    post = create_post(title: title)
    assert Posts::Save.call(post, translations: { "de" => { title: "Ein Ersatzzimmer" } }).ok?
    assert Posts::Save.call(post, translations: { "en" => { title: changed } }).ok?
    post.reload
  end

  def confirm_for(record, field = "title") = { record_type: record.class.name, record_id: record.id, field: field, locale: "de" }

  def render_outdated(record, field: "title", original: nil, kind: :plain, confirm: true)
    original ||= record.translation_value(field, "en")
    render_inline(Admin::EditorScreen::ReferenceCardComponent.new(
      field: field, locale: "de", original: original, kind: kind, state: :outdated, record: record,
      confirm: (confirm_for(record, field) if confirm)
    ))
  end

  test "an outdated card with a stored source shows the word diff and when it changed" do
    post = outdated_post

    render_outdated(post)

    assert_selector ".admin-reference-card.border-warn[data-translation-state='outdated']"
    assert_selector "del", text: "Removed: spare"
    assert_selector "ins", text: "Added: small"
    assert_selector "del > .sr-only", text: "Removed:"
    assert_selector "ins > .sr-only", text: "Added:"
    assert_no_selector "del[aria-label], ins[aria-label]"
    assert_selector ".admin-reference-card time"
    assert_selector ".admin-reference-card", text: /CHANGED/i
    assert_no_text "changed since this was translated"
  end

  test "the diff's del and ins use the handoff's tokens" do
    render_outdated(outdated_post)

    assert_selector "del.text-danger-ink.bg-danger-tint"
    assert_selector "ins.text-ok-ink.bg-ok-tint.underline"
  end

  test "the confirm button posts through the layout's confirm form, and says it is still correct" do
    post = outdated_post

    render_outdated(post)

    button = page.find(".admin-reference-card button[type='submit'][form='translation-confirm-form']", text: "Still correct — mark up to date")
    assert_equal "/cs-studio/translations/confirm", URI(button["formaction"]).path
    assert_equal({ "record_type" => "Post", "record_id" => post.id.to_s, "field" => "title", "locale" => "de" }, Rack::Utils.parse_query(URI(button["formaction"]).query))
  end

  test "a viewer who can't confirm sees the diff but no buttons" do
    render_outdated(outdated_post, confirm: false)

    assert_selector "del", text: "spare"
    assert_no_selector "button"
  end

  test "an entry without stored text gets the current original and the no-source sentence" do
    post = outdated_post
    post.update_columns(translation_sources: { "title" => { "de" => Translations.digest("A spare room") } })
    post.reload

    render_outdated(post)

    assert_selector ".admin-reference-card p", text: "A small room"
    assert_text "English changed since this was translated."
    assert_no_selector "del"
    assert_no_selector "ins"
  end

  test "stored text taken in another primary language is never diffed" do
    post = outdated_post
    sources = post.translation_sources.deep_dup
    sources["title"]["de"]["from"] = "fr"
    post.update_columns(translation_sources: sources)
    post.reload

    render_outdated(post)

    assert_text "English changed since this was translated."
    assert_no_selector "del"
  end

  test "a card with no record falls back to the no-source sentence" do
    render_card(state: :outdated, confirm: { record_type: "Post", record_id: 7, field: "title", locale: "de" })

    assert_text "English changed since this was translated."
    assert_selector "button[form='translation-confirm-form']", text: "Still correct — mark up to date"
    assert_no_selector ".admin-reference-card time"
  end

  test "a bold-only change to a rich body says Formatting changed" do
    post = create_post(title: "Rich")
    assert Posts::Save.call(post, translations: { "en" => { body: rich_doc("Hello world") } }).ok?
    assert Posts::Save.call(post, translations: { "de" => { body: rich_doc("Hallo Welt") } }).ok?
    assert Posts::Save.call(post, translations: { "en" => { body: rich_doc("**Hello world**") } }).ok?
    post.reload
    assert_equal :outdated, post.translation_state("body", "de")

    render_outdated(post, field: "body", kind: :rich)

    assert_text "Formatting changed"
    assert_selector "strong", text: "Hello world"
    assert_no_selector "del"
    assert_no_selector "ins"
  end

  test "a rich body diffs per paragraph" do
    post = create_post(title: "Rich")
    assert Posts::Save.call(post, translations: { "en" => { body: rich_doc("One\n\nTwo") } }).ok?
    assert Posts::Save.call(post, translations: { "de" => { body: rich_doc("Eins\n\nZwei") } }).ok?
    assert Posts::Save.call(post, translations: { "en" => { body: rich_doc("One\n\nThree") } }).ok?
    post.reload

    render_outdated(post, field: "body", kind: :rich)

    assert_selector "p", text: "One"
    assert_selector "del", text: "Two"
    assert_selector "ins", text: "Three"
  end

  test "a text too long to compare says so and shows the current original" do
    long = (%w[word] * (Translations::SourceDiff::MAX_WORDS + 5)).join(" ")
    post = outdated_post(title: long, changed: "#{long} more")

    render_outdated(post)

    assert_text "The text is too long to compare word by word."
    assert_no_selector "del"
  end

  test "original text and names are escaped, never trusted" do
    post = outdated_post(title: "Fine", changed: "Fine <script>alert(1)</script>")

    render_outdated(post)

    assert_selector "ins", text: "<script>alert(1)</script>"
    assert_no_selector "script"
  end

  test "the card has a stable DOM id" do
    post = outdated_post

    render_outdated(post)

    assert_equal "reference-card-post-#{post.id}-title-de", Admin::EditorScreen::ReferenceCardComponent.dom_id(post, "title", "de")
    assert_selector "##{Admin::EditorScreen::ReferenceCardComponent.dom_id(post, "title", "de")}.admin-reference-card"
  end

  test "current_for builds the current-state card for a record's field" do
    post = outdated_post
    post.confirm_translation("title", "de")
    post.save!

    render_inline Admin::EditorScreen::ReferenceCardComponent.current_for(post, "title", locale: "de")

    assert_selector "##{Admin::EditorScreen::ReferenceCardComponent.dom_id(post, "title", "de")}[data-translation-state='current'] p", text: "A small room"
    assert_no_selector "button"
  end

  class StubProvider
    def initialize(api_key:, model:); end
  end

  def suggest_for(post)
    Admin::TranslationScreen::TranslateButtonComponent.new(confirm: confirm_for(post), input_id: "post-title", characters: 12, mode: :update)
  end

  def render_with_suggest(post)
    render_inline(Admin::EditorScreen::ReferenceCardComponent.new(
      field: "title", locale: "de", original: "A small room", state: :outdated, record: post, confirm: confirm_for(post), suggest: suggest_for(post)
    ))
  end

  # The registry and `Current` are process-wide: put both back whatever happens.
  def with_ai(provider: "test/stub")
    Current.actor = users(:one)
    AI::Providers.register("test/stub", StubProvider)
    Current.site.update!(ai_provider: provider, ai_api_key: "sk-test")
    yield
  ensure
    Current.reset
    Rails.application.reloader.prepare!
  end

  test "the Suggest update button renders with its mode when AI is set up and the viewer may translate" do
    post = outdated_post

    with_ai { render_with_suggest(post) }

    assert_selector ".admin-reference-card [data-translate-mode='update'] button[data-action='admin--translation--translate#translate']", text: "Suggest update"
  end

  test "no Suggest update button without AI set up" do
    post = outdated_post

    with_ai(provider: nil) { render_with_suggest(post) }

    assert_no_selector "[data-translate-mode='update']"
    assert_no_text "Suggest update"
    assert_selector "button", text: "Still correct — mark up to date"
  end

  test "no Suggest update button for a viewer without ai.translate" do
    post = outdated_post

    with_ai do
      Current.actor = users(:reader)
      render_with_suggest(post)
    end

    assert_no_text "Suggest update"
  end

  test "a current card has no note" do
    render_card(state: :current)

    assert_no_text "Original changed"
  end

  test "is a collapsible details so it can fold away when stacked" do
    render_card(state: :current)

    assert_selector ".admin-reference-card > details[open] > summary"
  end
end
