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

  def render_field(value, original: nil, locale: "en", editable: true, **options)
    render_inline Admin::Ui::FieldComponent.new(field: field(**options), form_name: "block[settings]", value: value, original: original, locale: locale, id_prefix: "block-7", editable: editable)
  end

  def target(name) = "[data-#{CONTROLLER}-target='#{name}']"

  def wrapper = page.find("[data-controller='#{CONTROLLER}']")

  def textarea_text = Nokogiri::HTML5.fragment(rendered_content).at_css("textarea").text

  test "the Code field's textarea, named, with the source as typed, the source target, the counter's read and the preview's draw" do
    render_field(SOURCE)

    assert_selector "textarea#block-7-source[name='block[settings][source]'][wrap='off'][spellcheck='false'][autocapitalize='off'][autocomplete='off'][rows='12']"
    assert_selector "textarea.admin-code-input.font-cs-mono.whitespace-pre.overflow-auto#{target("source")}"
    assert_includes page.find("textarea")[:class].split, "[field-sizing:content]"
    assert_no_selector "textarea[maxlength]"
    assert_equal "input->admin--editor--code-limit#update input->#{CONTROLLER}#input", page.find("textarea")["data-action"]
    assert_equal [ "admin--diagram--preview#import", "change->admin--diagram--preview#read", page.find("textarea")["data-action"] ],
      page.all("[data-action]", visible: :all).map { |node| node["data-action"] }, "the import's, in the label's row, then the textarea's"
    assert_equal SOURCE, textarea_text
  end

  test "its wrapper is the preview's controller with the renderer, the rules, its messages, the drawing field and starting" do
    render_field(SOURCE)

    assert_selector ".admin-field[data-field-name='source'][data-controller='#{CONTROLLER}'] > .admin-mermaid-field"
    assert_equal "/cs-studio/diagram-renderer", wrapper["data-#{CONTROLLER}-renderer-url-value"]
    assert_equal Diagrams::Source.rules_json, wrapper["data-#{CONTROLLER}-rules-value"]
    assert_equal "block-7-drawing", wrapper["data-#{CONTROLLER}-drawing-field-value"]
    assert_equal "block[settings][drawing]", wrapper["data-#{CONTROLLER}-drawing-name-value"]
    assert_equal "block[settings][source]", wrapper["data-#{CONTROLLER}-source-name-value"]
    assert_equal "false", wrapper["data-#{CONTROLLER}-starting-value"]
    assert_equal BlockTypes.fetch(:diagram).themed_tokens.map { |name| "--th-#{name}" }, JSON.parse(wrapper["data-#{CONTROLLER}-colours-value"])

    served = JSON.parse(wrapper["data-messages"])
    assert_equal "Diagram preview", served.fetch("components.fields.mermaid_field.frame_title")
    assert_equal "Type a diagram to see it drawn.", served.fetch("components.fields.mermaid_field.empty")
    %w[error_lead kept nothing_yet kept_badge too_long too_large].each { |key| assert served.key?("components.fields.mermaid_field.#{key}"), key }
  end

  # The sentences are written once, under `errors.messages`, and the
  # script is handed those strings.
  test "the script's sentences for a refused line, a type and no type are the errors.messages strings" do
    render_field(SOURCE)
    served = JSON.parse(wrapper["data-messages"])

    Admin::Fields::MermaidField::SENTENCES.each do |key, sentence|
      assert_equal I18n.t(sentence), served.fetch(key), key
      assert sentence.start_with?("errors.messages.diagram_"), sentence
    end
    assert_equal %w[refused.colours refused.directive refused.front_matter refused.links refused.maths no_type unsupported],
      Admin::Fields::MermaidField::SENTENCES.keys.map { |key| key.delete_prefix("components.fields.mermaid_field.") }.sort_by { |key| [ key.start_with?("refused") ? 0 : 1, key ] }

    script = served.fetch("components.fields.mermaid_field.refused.colours").gsub(/%\{(\w+)\}/) { { "line" => "2", "word" => "classDef" }.fetch($1) }
    assert_equal I18n.t("errors.messages.diagram_colours", line: 2, word: "classDef"), script
  end

  test "the frame slot holds no frame and the state's words hidden, the status line is a polite region the server leaves empty, and the colour probe is hidden from everyone" do
    render_field(SOURCE)

    assert_no_selector "iframe", visible: :all
    slot = page.find(target("frameSlot"), visible: :all)
    assert slot.has_css?("p#{target("blank")}[hidden]:empty", visible: :all)
    assert slot.has_css?("span#{target("kept")}[hidden].bg-sunken.text-meta", text: "Last drawing that worked", visible: :all), "the neutral badge"
    assert slot.has_css?("span#{target("busy")}[hidden][aria-hidden='true']", text: "Drawing…", visible: :all)
    assert_selector "#{target("status")}[aria-live='polite']:empty", visible: :all
    assert_selector "span.content-block--diagram[aria-hidden='true'][hidden]#{target("colourProbe")}:empty", visible: :all
    assert_selector ".admin-mermaid-field__well > span#{target("line")}[hidden][aria-hidden='true']", visible: :all
  end

  test "with a description named, the neutral note is drawn hidden under the preview and the wrapper names the description's input" do
    render_field(SOURCE)
    assert_no_selector target("undescribed"), visible: :all
    assert_nil wrapper["data-#{CONTROLLER}-description-field-value"]

    render_field(SOURCE, description: :description)
    assert_equal "block-7-description", wrapper["data-#{CONTROLLER}-description-field-value"]
    note = page.find(".admin-mermaid-field__preview #{target("undescribed")}[hidden][role='note']", visible: :all)
    assert_equal "The site shows this diagram once it has a description.", note.text(:all)
    assert_equal (Admin::Ui::NoticeComponent.classes(:neutral, size: :compact).split + [ "mt-2" ]).sort, note[:class].split.sort
  end

  # The script clones the notice and fills its parts: no box is built by hand.
  test "the error's notice is the warn NoticeComponent in a template, compact, with no role of its own" do
    render_field(SOURCE)

    template = Nokogiri::HTML5.fragment(rendered_content).at_css("template#{target("notice")}")
    box = template.children.find(&:element?)
    assert_equal Admin::Ui::NoticeComponent.classes(:warn, size: :compact).split.sort, box["class"].split.sort
    assert_nil box["role"], "the live region speaks, not the notice"
    assert_equal %w[lead sentence message site], box.css("[data-part]").map { |part| part["data-part"] }
    assert_equal "pre", box.at_css("[data-part='message']").name
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

  test "the counter is the Code field's, from nine tenths of the limit, on its own script" do
    render_field("pie\n#{"x" * 8_000}")
    assert_selector "[data-controller='admin--editor--code-limit'][data-admin--editor--code-limit-limit-value='10000'][data-admin--editor--code-limit-from-value='9000'] textarea", visible: :all
    assert_selector "p#block-7-source-count[hidden][data-admin--editor--code-limit-target='output']", visible: :all
    assert_selector "p.sr-only[aria-live='polite'][data-admin--editor--code-limit-target='announcer']:empty", visible: :all

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
    assert_equal [ "input->admin--editor--code-limit#update" ], held.css("[data-action]").map { |node| node["data-action"] }, "only the counter's read survives"
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

  # Import file… (EditorDiagramBlock, "Importing"): a small tertiary button
  # at the end of the Source label's row, opening a hidden file input the
  # script reads in the browser. The input has no name, so no form sends it.
  test "Import file… is a small tertiary button at the end of the label's row, opening a hidden file input with no name" do
    render_field(SOURCE)

    row = page.find(".admin-field > .admin-field__label-row", visible: :all)
    assert_equal [ "label", "span" ], row.all(:xpath, "./*", visible: :all).map(&:tag_name)
    assert_equal "block-7-source", row.find("label")["for"]
    button = row.find("span.admin-mermaid-field__import > button[type='button']", exact_text: "Import file…")
    assert_equal Admin::Ui::ButtonComponent.classes(:tertiary, size: :small).split.sort, button[:class].split.sort
    assert_equal "#{CONTROLLER}#import", button["data-action"]

    file = row.find("span.admin-mermaid-field__import > input[type='file']#block-7-source-import[hidden]", visible: :all)
    assert_equal ".mmd,.md,text/markdown,text/plain", file["accept"]
    assert_nil file["name"], "the file is never sent"
    assert_equal "file", file["data-#{CONTROLLER}-target"]
    assert_equal "change->#{CONTROLLER}#read", file["data-action"]
    assert_equal "-1", file["tabindex"], "the button is the one stop"
  end

  test "a source that cannot be edited draws no Import control and no file input" do
    render_field(SOURCE, editable: false)

    assert_no_selector ".admin-mermaid-field__import, input[type='file'], .admin-field__label-row", visible: :all
    assert_no_text "Import file…"
    assert_selector "label[for='block-7-source']", exact_text: "Source"
    assert_nil wrapper["data-#{CONTROLLER}-replace-dialog-value"]
  end

  # What an import says comes from server markup the script clones: a
  # polite region under the source, the warn and neutral notices with no
  # role of their own inside it, and the "Imported from" line.
  test "an import's words stand in a polite region under the source, cloned from templates" do
    render_field(SOURCE)

    region = page.find(".admin-mermaid-field__pair > :first-child > #{target("importStatus")}[aria-live='polite']", visible: :all)
    assert_empty region.text(:all)
    fragment = Nokogiri::HTML5.fragment(rendered_content)
    box = ->(name) { fragment.at_css("template#{target(name)}").children.find(&:element?) }

    assert_equal (Admin::Ui::NoticeComponent.classes(:warn, size: :compact).split + [ "mt-2" ]).sort, box.call("importWarning")["class"].split.sort
    assert_equal (Admin::Ui::NoticeComponent.classes(:neutral, size: :compact).split + [ "mt-2" ]).sort, box.call("importNote")["class"].split.sort
    assert_nil box.call("importWarning")["role"]
    assert_nil box.call("importNote")["role"]
    line = box.call("imported")
    assert_equal "p", line.name
    assert_equal %w[mt-1 text-meta text-small], line["class"].split.sort
    assert_empty line.text

    assert_equal "block-7-source-replace", wrapper["data-#{CONTROLLER}-replace-dialog-value"]
    served = JSON.parse(wrapper["data-messages"])
    {
      "imported" => "Imported from %{file}.",
      "import_first_only" => "Only the first diagram in %{file} was imported.",
      "import_no_mermaid" => "%{file} holds no Mermaid diagram. A .md file needs a ```mermaid fence.",
      "import_too_long" => "%{file} is too long: its diagram has %{count} characters, and the limit is %{limit}.",
      "import_unreadable" => "%{file} couldn't be read. Use a .mmd or .md text file."
    }.each { |key, words| assert_equal words, served.fetch("components.fields.mermaid_field.#{key}"), key }
  end
end
