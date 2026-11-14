require "test_helper"

# `Admin::Fields::MermaidField` (Diagram block spec §7, EditorDiagramBlock):
# the Code field's textarea, beside an empty slot the preview script builds
# its frame in, a polite status line and the counter, all on
# `admin--diagram--preview`, which stands on the field's wrapper. Drawn as an
# editor draws it, inside `Admin::Ui::FieldComponent`.
class Admin::Fields::MermaidFieldTest < ViewComponent::TestCase
  Field = ContentModel::Definition::Field
  CONTROLLER = "admin--diagram--preview".freeze
  SOURCE = "flowchart LR\n  A --> B".freeze

  def field(**options) = Field.new(name: "source", type: :mermaid, options: { translated: true, drawing: :drawing, max: 10_000 }.merge(options))

  def render_field(value, original: nil, locale: "en", **options)
    render_inline Admin::Ui::FieldComponent.new(field: field(**options), form_name: "block[settings]", value: value, original: original, locale: locale, id_prefix: "block-7")
  end

  def target(name) = "[data-#{CONTROLLER}-target='#{name}']"

  def wrapper = page.find("[data-controller='#{CONTROLLER}']")

  def textarea_text = Nokogiri::HTML5.fragment(rendered_content).at_css("textarea").text

  test "the Code field's textarea, named, with the source as typed, the source target and no action of its own" do
    render_field(SOURCE)

    assert_selector "textarea#block-7-source[name='block[settings][source]'][wrap='off'][spellcheck='false'][autocapitalize='off'][autocomplete='off'][rows='12']"
    assert_selector "textarea.admin-code-input.font-cs-mono.whitespace-pre.overflow-auto#{target("source")}"
    assert_includes page.find("textarea")[:class].split, "[field-sizing:content]"
    assert_no_selector "textarea[maxlength], [data-action]"
    assert_equal SOURCE, textarea_text
  end

  test "its wrapper is the preview's controller with the renderer, the rules, its messages, the drawing field and starting" do
    render_field(SOURCE)

    assert_selector ".admin-field[data-field-name='source'][data-controller='#{CONTROLLER}'] > .admin-mermaid-field"
    assert_equal "/cs-studio/diagram-renderer", wrapper["data-#{CONTROLLER}-renderer-url-value"]
    assert_equal Diagram::Source.rules_json, wrapper["data-#{CONTROLLER}-rules-value"]
    assert_equal "block-7-drawing", wrapper["data-#{CONTROLLER}-drawing-field-value"]
    assert_equal "block[settings][drawing]", wrapper["data-#{CONTROLLER}-drawing-name-value"]
    assert_equal "block[settings][source]", wrapper["data-#{CONTROLLER}-source-name-value"]
    assert_equal "false", wrapper["data-#{CONTROLLER}-starting-value"]
    assert_equal "10000", wrapper["data-#{CONTROLLER}-limit-value"]
    assert_equal "9000", wrapper["data-#{CONTROLLER}-from-value"]

    served = JSON.parse(wrapper["data-messages"])
    assert_equal "Diagram preview", served.fetch("components.fields.mermaid_field.frame_title")
    assert_equal "Type a diagram to see it drawn.", served.fetch("components.fields.mermaid_field.empty")
    %w[count over drawing no_description error_lead kept nothing_yet kept_badge].each { |key| assert served.key?("components.fields.mermaid_field.#{key}"), key }
  end

  # The sentences are written once, under `errors.messages`, and the
  # script is handed those strings: what the card says of a refused line is
  # what a refused save says.
  test "the script's sentences for a refused line, a type and no type are the server's own strings" do
    render_field(SOURCE)
    served = JSON.parse(wrapper["data-messages"])

    Admin::Fields::MermaidField::SENTENCES.each do |key, error|
      assert_equal I18n.t("errors.messages.#{error}"), served.fetch("components.fields.mermaid_field.#{key}"), key
    end
    assert_equal %w[refused.colours refused.directive refused.front_matter refused.links refused.maths no_type unsupported],
      Admin::Fields::MermaidField::SENTENCES.keys.sort_by { |key| [ key.start_with?("refused") ? 0 : 1, key ] }

    definition = ContentModel::BlockTypeDefinition.new("sample").tap do |t|
      t.field :source, :mermaid, drawing: :drawing
      t.field :drawing, :diagram_drawing
    end
    server = definition.field_set.new({}).assign("source" => "flowchart LR\n  classDef a fill:red").tap(&:valid?).errors[:source]
    script = served.fetch("components.fields.mermaid_field.refused.colours").gsub(/%\{(\w+)\}/) { { "line" => "2", "word" => "classDef" }.fetch($1) }
    assert_equal server, [ script ]
  end

  test "the frame slot is empty, the status line is a polite region the server leaves empty, and the colour probe is hidden from everyone" do
    render_field(SOURCE)

    assert_selector "#{target("frameSlot")}:empty", visible: :all
    assert_no_selector "iframe", visible: :all
    assert_selector "#{target("status")}[aria-live='polite']:empty", visible: :all
    assert_selector "span.content-block--diagram[aria-hidden='true'][hidden]#{target("colourProbe")}:empty", visible: :all
  end

  # The pair is two equal columns while the field has 40rem, stacked below:
  # a wrapping row, because no size container may stand inside the post
  # form (`test/lib/admin_design_rules_test.rb`).
  test "the source and the preview stand in one row, the source first" do
    render_field(SOURCE)

    halves = page.all(".admin-mermaid-field__pair > *", visible: :all)
    assert_equal 2, halves.size
    assert halves.first.has_css?("textarea")
    assert halves.last.has_css?(target("frameSlot"), visible: :all)
  end

  test "the counter is the Code field's, from nine tenths of the limit, and the counter target" do
    render_field("pie\n#{"x" * 8_000}")
    assert_selector "p#block-7-source-count[hidden]#{target("counter")}", visible: :all

    render_field("pie\n#{"x" * 9_408}")
    assert_selector "p#block-7-source-count:not([hidden])", exact_text: "9,412 of 10,000 characters"
    assert_selector "textarea[aria-describedby='block-7-source-count']"

    render_field("pie\n#{"x" * 10_236}")
    assert_selector "p#block-7-source-count.text-danger-ink", exact_text: "10,240 of 10,000 characters · 240 over"
  end

  test "MermaidField on a translation tab with no source of its own shows the original's source with no name attribute" do
    render_field(nil, original: SOURCE, locale: "de")

    assert_selector "textarea#block-7-source:not([name])"
    assert_equal SOURCE, textarea_text
    assert_equal "true", wrapper["data-#{CONTROLLER}-starting-value"]
    assert_equal "block[settings][source]", wrapper["data-#{CONTROLLER}-source-name-value"]
    assert_selector "p#block-7-source-starting", text: "Starts from the English diagram. It becomes this language's own when you change it."
    assert_includes page.find("textarea")["aria-describedby"].to_s.split, "block-7-source-starting"

    render_field("flowchart LR\n  X --> Y", original: SOURCE, locale: "de")
    assert_selector "textarea#block-7-source[name='block[settings][source]']"
    assert_equal "false", wrapper["data-#{CONTROLLER}-starting-value"]
    assert_no_selector "#block-7-source-starting"
  end

  test "MermaidField in a held form is readonly and still carries its controller" do
    render_field(SOURCE)
    held = Nokogiri::HTML5.fragment(Admin::EditorScreen::HeldFields.call(rendered_content))

    assert_equal "readonly", held.at_css("textarea")["readonly"]
    assert held.at_css("[data-controller='#{CONTROLLER}']")
    assert held.at_css(target("frameSlot"))
    assert_nil held.at_css("[data-action]")
  end

  test "it reads as code where it cannot be edited" do
    assert_equal SOURCE, Admin::Fields::MermaidField.display(field, SOURCE).text
    assert_nil Admin::Fields::MermaidField.display(field, nil)
  end

  # Held by someone else on a translation tab with no source of its own: the
  # original's source, read-only, still said to be the starting text, so it
  # never reads as this language's own.
  test "a held card on a translation tab with no source of its own shows the original read-only with the starting line" do
    render_field(nil, original: SOURCE, locale: "de")
    held = Nokogiri::HTML5.fragment(Admin::EditorScreen::HeldFields.call(rendered_content))
    textarea = held.at_css("textarea#block-7-source")

    assert_equal "readonly", textarea["readonly"]
    assert_nil textarea["name"]
    assert_equal SOURCE, textarea.text
    assert_equal "Starts from the English diagram. It becomes this language's own when you change it.", held.at_css("p#block-7-source-starting").text
    assert_includes textarea["aria-describedby"].split, "block-7-source-starting"
  end

  # The original is code: shown in the frame CS Studio shows code it does
  # not edit in (`admin/shared/_code_display`), its indentation kept.
  test "on a translation tab the original source is a code frame in the reference card" do
    original = "flowchart LR\n    A --> B\n\tB --> C"
    render_field("flowchart LR\n  X --> Y", original: original, locale: "de")

    pre = Nokogiri::HTML5.fragment(rendered_content).at_css(".admin-translation-pair [data-original-for='source'] pre")
    assert pre, "the original is a pre"
    assert_includes pre[:class].split, "font-cs-mono"
    assert_includes pre[:class].split, "bg-sunken"
    assert_nil Nokogiri::HTML5.fragment(rendered_content).at_css("[data-original-for='source'] p.whitespace-pre-line"), "not the plain paragraph, which folds the indentation"
    assert_equal original, pre.text
    assert_equal :code, Admin::Ui::ReferenceCardComponent.kind_for(original, field)
    assert_equal :plain, Admin::Ui::ReferenceCardComponent.kind_for("Hallo", Field.new(name: "title", type: :string, options: {}))
  end

  test "on a translation tab the preview stands under the whole pair, inside the field's controller" do
    render_field("flowchart LR\n  X --> Y", original: SOURCE, locale: "de")
    fragment = Nokogiri::HTML5.fragment(rendered_content)

    assert_nil fragment.at_css(".admin-translation-pair #{target("frameSlot")}"), "not beside the source"
    below = fragment.at_css(".admin-field[data-controller='#{CONTROLLER}'] > .admin-translation-pair + .admin-mermaid-field__below")
    assert below, "the preview follows the pair"
    assert below.at_css(target("frameSlot"))
    assert below.at_css("#{target("status")}[aria-live='polite']")
    assert_equal 1, fragment.css(target("frameSlot")).size
  end
end
