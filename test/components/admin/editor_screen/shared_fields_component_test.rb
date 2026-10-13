require "test_helper"

class Admin::EditorScreen::SharedFieldsComponentTest < ViewComponent::TestCase
  Field = ContentModel::Definition::Field

  test "is closed by default, counts its fields and lists label and value read-only" do
    render_inline(Admin::EditorScreen::SharedFieldsComponent.new(fields: [ [ "Venue", "Main Hall" ], [ "Limit", "5" ] ]))

    assert_selector "details:not([open]) > summary", text: "Shared fields (2)"
    assert_text "Venue"
    assert_text "Main Hall"
    assert_text "Limit"
    assert_text "Shared by all languages. Edit them on the #{Locales.name(Locales.default, native: true)} tab."
    assert_no_selector "input, textarea, select"
  end

  test "renders nothing without fields" do
    render_inline(Admin::EditorScreen::SharedFieldsComponent.new(fields: []))

    assert_no_selector "details"
  end

  test "a blank value reads as a dash" do
    render_inline(Admin::EditorScreen::SharedFieldsComponent.new(fields: [ [ "Venue", "" ] ]))

    assert_text "—"
  end

  test "a select is shown by its label, an empty one by its blank label, and a value that is not on the list as it is stored" do
    field = Field.new(name: "language", type: :select, options: { options: { "ruby" => "Ruby" }, blank: "Plain text" })
    display = ->(value) { Admin::EditorScreen::SharedFieldsComponent.display(field, value) }

    assert_equal "Ruby", display.("ruby")
    assert_equal "Plain text", display.(nil)
    assert_equal "cobol", display.("cobol")
    assert_equal "small", Admin::EditorScreen::SharedFieldsComponent.display(Field.new(name: "size", type: :select, options: { options: %w[small] }), "small")
  end

  # Design answer C6.
  test "code keeps its frame in a scrolling pre of at most twelve lines, as text in full ink, under one small line that says where it is edited; no code is a dash" do
    field = Field.new(name: "code", type: :code, options: {})
    shown = Admin::EditorScreen::SharedFieldsComponent.display(field, "  a <b>bold</b>\n\tb")
    assert_nil Admin::EditorScreen::SharedFieldsComponent.display(field, nil)

    render_inline(Admin::EditorScreen::SharedFieldsComponent.new(fields: [ [ "Code", shown ], [ "File name", nil ] ], primary_url: "/cs-studio/pages/7"))

    assert_selector "dd pre[tabindex='0'].overflow-auto.bg-sunken.border.border-line.rounded-cs.font-cs-mono.text-ink", visible: :all
    assert_includes page.find("dd pre", visible: :all)[:class], "max-h-[12lh]"
    assert_equal "  a <b>bold</b>\n\tb", Nokogiri::HTML5.fragment(rendered_content).at_css("dd pre").text
    assert_no_selector "dd b", visible: :all
    assert_text :all, "—"

    name = Locales.name(Locales.default, native: true)
    assert_selector "dd > p.text-xs.text-meta + pre", visible: :all
    assert_equal "Code isn't translated. Edit it on the #{name} tab.", page.find("dd > p[data-code-note]", visible: :all).text(:all)
    assert_selector "dd > p[data-code-note] a[href='/cs-studio/pages/7'][data-turbo-frame='_top']", exact_text: name, visible: :all, count: 1
    assert_selector "p[data-code-note]", visible: :all, count: 1
  end

  test "without the default tab's address the language is named and not linked, and a language's name is text" do
    shown = Admin::EditorScreen::SharedFieldsComponent.display(Field.new(name: "code", type: :code, options: {}), "a")

    render_inline(Admin::EditorScreen::SharedFieldsComponent.new(fields: [ [ "Code", shown ] ]))
    assert_no_selector "p[data-code-note] a", visible: :all
    assert_equal "Code isn't translated. Edit it on the #{Locales.name(Locales.default, native: true)} tab.", page.find("p[data-code-note]", visible: :all).text(:all)

    with_singleton_override(Locales, :name, ->(*, **) { "<i>Ελληνικά</i>" }) do
      render_inline(Admin::EditorScreen::SharedFieldsComponent.new(fields: [ [ "Code", shown ] ], primary_url: "/x"))
    end
    assert_no_selector "p[data-code-note] i", visible: :all
    assert_selector "p[data-code-note] a", exact_text: "<i>Ελληνικά</i>", visible: :all
  end

  # Task 2's review, Minor 6: a browser drops one line break directly after
  # `<pre>`. The template writes one of its own there, so a value that begins
  # with one keeps it, also through the held form's rewrite.
  test "code that begins with a line break keeps it in the pre's markup, also in a held form" do
    [ "\n  a\n\nb", "  a\n\nb", "\n\n" ].each do |text|
      render_inline(Admin::EditorScreen::SharedFieldsComponent.new(fields: [ [ "Code", Admin::EditorScreen::SharedFieldsComponent::Code.new(text) ] ]))

      assert_equal text, Nokogiri::HTML5.fragment(rendered_content).at_css("dd pre").text, text.inspect
      assert_equal text, Nokogiri::HTML5.fragment(Admin::EditorScreen::HeldFields.call(rendered_content)).at_css("dd pre").text, "held: #{text.inspect}"
    end
  end
end
