require "test_helper"

# One AI suggestion under a field's original (translation helpers spec
# §6.4): the text or a rich-text preview, Use/Discard as plain buttons
# (never submits -- these sit inside autosave forms), the warnings, and the
# inline error variant. Use itself is `admin--translate#use`, exercised by
# the system tests.
class Admin::TranslationScreen::SuggestionComponentTest < ViewComponent::TestCase
  setup { Current.actor = users(:one) }

  def doc(markdown) = RichText::Document.from_markdown(markdown).first

  test "dom_id is keyed by the input it fills" do
    assert_equal "translation-suggestion-post-title", Admin::TranslationScreen::SuggestionComponent.dom_id("post-title")
  end

  test "a plain suggestion is editable and names the model that wrote it" do
    render_inline(Admin::TranslationScreen::SuggestionComponent.new(input_id: "post_title", locale: "de", suggestion: "Hallo Welt",
      model: "claude-sonnet-5"))
    assert_selector "[data-translation-suggestion].bg-accent-tint"
    assert_selector "textarea[data-translate-suggestion-text][aria-label='Suggested translation']", text: "Hallo Welt"
    assert_no_selector "textarea[name]", visible: :all
    assert_text(/suggested by claude-sonnet-5/i)
    assert_selector "button", text: "Use"
    assert_selector "button", text: "Discard"
  end

  test "Use names its input and no longer carries the text (the textarea's current value is applied)" do
    render_inline Admin::TranslationScreen::SuggestionComponent.new(input_id: "post-title", locale: "de", suggestion: "Hallo")

    use = page.find("button[type='button'][data-translate-use]", text: "Use")
    assert_equal "plain", use["data-translate-kind"]
    assert_equal "post-title", use["data-translate-input-id"]
    assert_nil use["data-translate-text"]
    assert_equal "admin--translate#use", use["data-action"]
    assert_selector "button[type='button'][data-action='admin--translate#discard']", text: "Discard"
    refute_selector "[role='alert']"
  end

  test "the box keeps its edits from the form's autosave" do
    render_inline Admin::TranslationScreen::SuggestionComponent.new(input_id: "post-title", locale: "de", suggestion: "Hallo")

    actions = page.find("[data-translation-suggestion]")["data-action"]
    %w[input change focusout].each { |event| assert_includes actions, "#{event}->admin--translate#contain" }
  end

  test "without a model name it just says Suggested translation" do
    render_inline(Admin::TranslationScreen::SuggestionComponent.new(input_id: "post_title", locale: "de", suggestion: "Hallo"))
    assert_text(/suggested translation/i)
    assert_no_text(/suggested by/i)
  end

  test "the suggestion text is escaped inside the textarea" do
    render_inline(Admin::TranslationScreen::SuggestionComponent.new(input_id: "t", locale: "de", suggestion: "</textarea><script>x</script>"))
    assert_no_selector "script", visible: :all
    assert_selector "textarea", text: "</textarea><script>x</script>"
  end

  test "a rich-text suggestion: the scrubbed preview, the document to load, and its warnings" do
    suggestion = doc("Hallo **Welt**")
    render_inline Admin::TranslationScreen::SuggestionComponent.new(input_id: "post-body-json", locale: "de", suggestion: suggestion,
      warnings: [ "Unknown directive ::foo was kept as text" ])

    assert_selector ".admin-rich-text-content strong", text: "Welt"
    use = page.find("button[data-translate-use]")
    assert_equal "rich", use["data-translate-kind"]
    assert_equal "post-body-json", use["data-translate-input-id"]
    assert_equal suggestion.to_h, JSON.parse(use["data-translate-document"])
    assert_equal({}, JSON.parse(use["data-translate-assets"]))
    assert_equal({}, JSON.parse(use["data-translate-link-titles"]))
    assert_selector "li", text: "Unknown directive ::foo was kept as text"
  end

  test "a rich-text suggestion's images travel with Use, so the editor can show them" do
    asset = create_media_asset
    render_inline Admin::TranslationScreen::SuggestionComponent.new(input_id: "post-body-json", locale: "de",
      suggestion: doc(%(::image{asset="#{asset.id}"})))

    assets = JSON.parse(page.find("button[data-translate-use]")["data-translate-assets"])
    assert_equal [ asset.id.to_s ], assets.keys
    assert assets[asset.id.to_s]["url"].present?
  end

  test "the error variant: the message as an alert, Dismiss, no Use" do
    render_inline Admin::TranslationScreen::SuggestionComponent.new(input_id: "post-title", locale: "de", error: "The AI provider is busy")

    assert_selector "[role='alert']", text: "The AI provider is busy"
    assert_selector "button[type='button'][data-action='admin--translate#discard']", text: "Dismiss"
    refute_selector "[data-translate-use]"
  end
end
