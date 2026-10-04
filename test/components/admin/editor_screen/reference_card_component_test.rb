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

  test "a rich original is rendered HTML, scrubbed" do
    document = RichText::Document.new(
      "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "Hello <script>alert(1)</script>", "marks" => [ { "type" => "bold" } ] } ] } ]
    )

    render_card(field: "body", original: document, kind: :rich)

    assert_selector "[data-original-for='body'] strong", text: "Hello"
    assert_no_selector "script"
  end

  test "an outdated card keeps the note and its Mark as up to date button" do
    confirm = { record_type: "Post", record_id: 7, field: "title", locale: "de" }

    render_card(state: :outdated, confirm: confirm)

    assert_selector ".admin-reference-card [data-translation-state='outdated']", text: "Original changed since this was translated"
    assert_selector ".admin-reference-card button[form='translation-confirm-form']", text: "Mark as up to date"
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
