require "test_helper"

# `HeldFields` rewrites a rendered form once, on the server, instead of each of
# the eight field components learning a read-only option (plan "disagrees" 5,
# open point 7). The rewrite is proven here, per field kind, by comparing every
# element of the form before and after: nothing but the read-only attributes
# and the neutralised actions may differ.
class Admin::EditorScreen::HeldFieldsTest < ViewComponent::TestCase
  include ContentHelper
  include TestTypes

  # The CMS's own four, decided HERE (the file's rule: a new survivor fails
  # until someone classifies it). A type's own read-only actions are its
  # definition's (block types spec, decision 10), checked against its
  # controller file below.
  CMS = %w[
    admin--editor--slug-preview#update
    admin--rich-text--editor#containFocus
    admin--ui--menu#select
    admin--ui--menu#close
  ].freeze

  def held(html, **options) = Admin::EditorScreen::HeldFields.call(html, **options)

  test "text controls are readonly, the rest is disabled, hidden fields and values are untouched" do
    html = %(<input type="hidden" name="base_updated_at" value="t"><input type="text" name="a" value="x &amp; y"><textarea name="b">text</textarea>
             <select name="c"><option selected>one</option></select><input type="checkbox" name="d" checked><button type="button">Choose</button>)

    page = Capybara.string(held(html))

    assert page.has_css?("input[name=a][readonly][value='x & y']:not([disabled])")
    assert page.has_css?("textarea[name=b][readonly]", text: "text")
    assert page.has_css?("select[name=c][disabled]") && page.has_css?("input[name=d][disabled][checked]") && page.has_css?("button[disabled]")
    assert page.has_css?("input[type=hidden][name=base_updated_at]:not([readonly]):not([disabled])", visible: :all)
  end

  test "a newline that starts a textarea or a pre survives the parse, which drops the first one" do
    html = %(<textarea name="a">\n\nfirst blank line</textarea><pre>\n\n  indented</pre><textarea name="b">\n</textarea>)

    again = Nokogiri::HTML5.fragment(held(html))

    assert_equal "\nfirst blank line", again.at_css("textarea[name=a]").text
    assert_equal "\n  indented", again.at_css("pre").text
    assert_equal "", again.at_css("textarea[name=b]").text
  end

  test "templates, JSON scripts, SVG, entities and boolean attributes come out as they went in" do
    html = %(<div hidden data-x='a"b'><template data-t="x"><li><input type="hidden" name="a" value="v"><button type="button" data-action="a#b"><span>×</span></button></li></template>
             <script type="application/json">{"a":"&lt;b&gt;","b":"x &amp; y"}</script><svg viewBox="0 0 1 1"><path d="M0 0"/></svg><p>&nbsp;x &amp; y &lt;z&gt;</p></div>)

    assert_same_markup html, held(html)
  end

  test "every action not on the allow-list is removed, from any element, with any target, option or key filter" do
    html = %(<div data-action="click->admin--editor--groups#add">a</div><ul data-action="keydown.enter->admin--editor--groups#add">b</ul><a href="/x" data-action="click->admin--editor--groups#add:stop">c</a>
             <summary data-action="media-picker:picked@window->admin--editor--groups#add:once">d</summary>
             <span data-action="admin--editor--groups#add@document admin--rich-text--editor#containFocus">e</span>
             <span data-action="focusout->admin--rich-text--editor#containFocus">f</span>
             <span data-action="focusout->admin--rich-text--editor#containFocus:stop@window">g</span>
             <button type="button" data-action="click->admin--editor--blocks#toggle">expand</button>)

    page = Nokogiri::HTML5.fragment(held(html))

    assert_equal [ "admin--rich-text--editor#containFocus", "focusout->admin--rich-text--editor#containFocus", "focusout->admin--rich-text--editor#containFocus:stop@window" ],
      page.css("[data-action]").map { |node| node["data-action"] }
    assert_empty page.css("[data-action*='groups'], [data-action*='toggle']")
  end

  # The control table. Each type is decided here, on purpose.
  CONTROLS = {
    "text" => :readonly, "search" => :readonly, "tel" => :readonly, "url" => :readonly, "email" => :readonly, "password" => :readonly,
    "number" => :readonly, "date" => :readonly, "datetime-local" => :readonly, "month" => :readonly, "week" => :readonly, "time" => :readonly,
    "checkbox" => :disabled, "radio" => :disabled, "file" => :disabled, "range" => :disabled, "color" => :disabled,
    "submit" => :disabled, "button" => :disabled, "reset" => :disabled, "image" => :disabled, "hypothetical" => :disabled,
    "hidden" => :untouched
  }.freeze

  test "each input type is made read-only the way it can be: readonly, disabled or left alone; an unknown type is disabled" do
    CONTROLS.each do |type, expected|
      field = Nokogiri::HTML5.fragment(held(%(<input type="#{type}" name="x" value="v">))).at_css("input")

      assert_equal expected == :readonly, field.key?("readonly"), "#{type} readonly"
      assert_equal expected == :disabled, field.key?("disabled"), "#{type} disabled"
    end
    assert Nokogiri::HTML5.fragment(held(%(<input name="x">))).at_css("input").key?("readonly"), "no type is text"
    assert Nokogiri::HTML5.fragment(held(%(<input type="TEXT" name="x">))).at_css("input").key?("readonly"), "the type is case-insensitive"
    assert Nokogiri::HTML5.fragment(held(%(<select name="x"></select><button>b</button><textarea name="t"></textarea>))).css("select, button").all? { |node| node.key?("disabled") }
    assert Nokogiri::HTML5.fragment(held(%(<textarea name="t"></textarea>))).at_css("textarea").key?("readonly")
  end

  test "the guard is a disabled submit button first in the form, so Enter in a field submits nothing" do
    page = Capybara.string(held(%(<input type="text" name="a">), guard: true))

    assert page.has_css?("button[type=submit][disabled][data-held-guard]:first-child", visible: :all)
    assert Capybara.string(held(%(<input type="text" name="a">))).has_no_css?("[data-held-guard]", visible: :all)
  end

  # Element by element, in document order (templates included): the attributes, minus the ones
  # this rewrite sets, are the same, and so is every text.
  def assert_same_markup(before_html, after_html, ignore: %w[readonly disabled])
    before = Nokogiri::HTML5.fragment(before_html)
    after = Nokogiri::HTML5.fragment(after_html.to_s)
    before_nodes = before.css("*")
    after_nodes = after.css("*").reject { |node| node["data-held-guard"] }
    assert_equal before_nodes.size, after_nodes.size

    before_nodes.zip(after_nodes).each do |was, now|
      assert_equal was.name, now.name
      assert_equal comparable(was, ignore), comparable(now, ignore), "<#{was.name}> #{was['name'] || was['id']}"
      assert_equal was.children.select(&:text?).map(&:content), now.children.select(&:text?).map(&:content), "text of <#{was.name}> #{was['name'] || was['id']}"
    end
  end

  # data-action is compared by the allow-list tests below, with their own list; here it is left out.
  def comparable(node, ignore)
    node.attributes.transform_values(&:value).except(*ignore, "data-action").sort.to_h
  end

  # Whether each of the eight field components survives the parse and the rewrite: a real
  # form, rendered editable, rewritten, compared control by control.
  # The actions that may live on in a held form, decided HERE and not read from the implementation:
  # a new one fails every test that calls `assert_survives` until someone classifies it.
  ALLOWED = [
    "input->admin--editor--slug-preview#update",
    "focusout->admin--rich-text--editor#containFocus",
    "click->admin--ui--menu#select",
    "click->admin--ui--menu#close",
    "input->admin--editor--code-limit#update" # the Code type's declared action
  ].freeze

  def assert_survives(html)
    rewritten = held(html)
    left = Nokogiri::HTML5.fragment(rewritten).css("[data-action]").flat_map { |node| node["data-action"].split }
    assert_empty left.uniq - ALLOWED, "an action survives in a held form that nobody has classified as read-only"
    # The original's actions minus the neutralised ones are what is left; everything else is identical.
    assert_same_markup(html, rewritten)
    reparsed = Nokogiri::HTML5.fragment(rewritten)
    Nokogiri::HTML5.fragment(html).css("textarea, pre").zip(reparsed.css("textarea, pre")).each { |was, now| assert_equal was.text, now.text }
    assert_empty reparsed.css("input:not([type=hidden]):not([type=checkbox]):not([type=radio]):not([type=file]):not([type=submit]):not([type=button]):not([readonly]), textarea:not([readonly])")
    assert_empty reparsed.css("select:not([disabled]), button:not([disabled])")
  end

  test "Admin::Ui::FieldComponent (a block's schema fields), rewritten, differs only in what it should" do
    page = create_page(title: "Fields")
    block = page.content_blocks.create!(block_type: "post_list", position: 0, settings: { "limit" => 3 })
    render_inline Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "en", editable: true)

    assert_survives(rendered_content)
  end

  test "Admin::Fields::CodeField, rewritten: the code is read-only with its indentation and its counter's action is the one left" do
    field = ContentModel::Definition::Field.new(name: "code", type: :code, options: { max: 20_000 })
    render_inline Admin::Ui::FieldComponent.new(field: field, form_name: "block[settings]", value: "    indented\n\tb", locale: "en", id_prefix: "block-1")

    assert_survives(rendered_content)
    rewritten = Nokogiri::HTML5.fragment(held(rendered_content))
    assert rewritten.at_css("textarea[name='block[settings][code]'][readonly]")
    assert_equal "    indented\n\tb", rewritten.at_css("textarea").text
    assert_equal [ "input->admin--editor--code-limit#update" ], rewritten.css("[data-action]").map { |node| node["data-action"] }
  end

  test "Admin::Ui::ChipInputComponent and RelatedPostsComponent (a post's tags, a block's tag), rewritten" do
    post = create_post(title: "Chips", tags: [ "alpha", "beta" ])
    as_owner { render_inline Admin::EditorScreen::PostFormComponent.new(post: post, locale: "en") }

    assert_survives(rendered_content)
    assert_match(/chip-input/, rendered_content)
  end

  test "Admin::Columns::PlainColumnComponent and SlugColumnComponent (the page settings), rewritten" do
    page = create_page(title: "Plain and slug", published: false)
    as_owner { render_inline Admin::EditorScreen::PageSettingsFormComponent.new(page: page, locale: "en") }

    assert_selector "input[name='page[slug]']"
    assert_survives(rendered_content)
  end

  test "the Change address button of a held settings form is disabled" do
    page = create_page(title: "Held address")
    reserve(page, page, users(:two), "tab-bbbbbbbb")
    as_viewer(users(:one), tab: "tab-aaaaaaaa") { render_inline Admin::EditorScreen::PageSettingsFormComponent.new(page: page, locale: "en") }

    assert_selector "fieldset.admin-held button[disabled]", text: "Change address…"
    assert_no_selector "button[data-action*='dialog']:not([disabled])", text: "Change address…"
  end

  test "Admin::Columns::RichTextColumnComponent (a rich-text block), rewritten, with a body that holds an ampersand and a less-than" do
    page = create_page(title: "Rich")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0, body: rich_doc("Hello & goodbye < friends"))
    render_inline Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "en", editable: true)

    assert_survives(rendered_content)
  end

  test "Admin::Columns::MediaColumnComponent (an image block), rewritten" do
    page = create_page(title: "Media")
    block = page.content_blocks.create!(block_type: "image", position: 0, media_asset: create_media_asset)
    as_owner { render_inline Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "en", editable: true) }

    assert_selector "[data-admin--media--field-target=choose]", visible: :all
    assert_survives(rendered_content)
  end

  test "the section's selects and its layout menu, rewritten" do
    page = create_page(title: "Section")
    section = page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "two" })
    outline = BlockOutline.new(page.content_blocks.reload)
    render_inline Admin::EditorScreen::SectionCardComponent.new(page: page, section: outline.top_level.first, outline: outline, locale: "en", editable: true)

    assert_selector "#section-#{section.id}-form select", count: 2
    assert_survives(rendered_content)
  end

  test "a translation tab's pair, with the original beside the field, rewritten" do
    with_locales(%w[en de], default: "en") do
      page = create_page(title: "Pair", translations: { "de" => { title: "Paar" } })
      as_owner { render_inline Admin::EditorScreen::PageSettingsFormComponent.new(page: page, locale: "de") }

      assert_survives(rendered_content)
    end
  end

  test "the rules the browser's freeze reads are this module's own lists, and nothing else" do
    rules = Admin::EditorScreen::HeldFields.rules

    assert_equal %i[allowed_actions hidden_types readonly_types], rules.keys.sort
    assert_equal Admin::EditorScreen::HeldFields.allowed_actions, rules[:allowed_actions]
    assert_same Admin::EditorScreen::HeldFields::READONLY_TYPES, rules[:readonly_types]
    assert_same Admin::EditorScreen::HeldFields::HIDDEN_TYPES, rules[:hidden_types]
  end

  test "the allow-list is the CMS's four and every type's declared read-only actions, each a method of a controller file" do
    assert_equal CMS, Admin::EditorScreen::HeldFields::CMS_ACTIONS
    declared = BlockTypes.all.flat_map(&:read_only_actions)
    assert_includes declared, "admin--editor--code-limit#update", "the Code type declares its counter"
    assert_equal (CMS + declared).uniq, Admin::EditorScreen::HeldFields.allowed_actions

    declared.each do |action|
      identifier, method = action.split("#")
      file = Rails.root.join("app/javascript/controllers", "#{identifier.split("--").join("/").tr("-", "_")}_controller.js")
      assert file.file?, "#{action} names no controller file (#{file.relative_path_from(Rails.root)})"
      assert_match(/^\s*(?:async\s+)?#{Regexp.escape(method)}\s*\(/, file.read, "#{action}: the controller defines no #{method}")
    end
  end

  test "an action a type declares survives in a held form, and only while the type declares it" do
    html = %(<input type="text" name="block[settings][text]" data-action="input->admin--ui--char-count#update">)
    assert_empty Nokogiri::HTML5.fragment(held(html)).css("[data-action]")

    with_test_types do
      BlockTypes.fetch("test/quote").read_only_actions("admin--ui--char-count#update")
      assert_equal "input->admin--ui--char-count#update", Nokogiri::HTML5.fragment(held(html)).at_css("input")["data-action"]
    end
  end

  test "a code block's card, rewritten; held by someone else its code is read-only with its indentation, its select disabled, and no save is wired" do
    page = create_page(title: "Held code")
    block = page.content_blocks.create!(block_type: "code", position: 0, settings: { "language" => "ruby", "filename" => "a.rb", "code" => "    indented\n\tb" })
    as_owner { render_inline Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "en", editable: true) }
    assert_survives(rendered_content)

    reserve(block, page, users(:two), "tab-bbbbbbbb")
    as_viewer(users(:one), tab: "tab-aaaaaaaa") { render_inline Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "en") }

    assert_selector "fieldset.admin-held textarea[name='block[settings][code]'][readonly]"
    assert_equal "    indented\n\tb", Nokogiri::HTML5.fragment(rendered_content).at_css("textarea[name='block[settings][code]']").text
    assert_selector "fieldset.admin-held select[name='block[settings][language]'][disabled]"
    assert_selector "fieldset.admin-held input[name='block[settings][filename]'][readonly]"
    assert_no_selector "[data-controller~='admin--saving--autosave']"
    left = Nokogiri::HTML5.fragment(rendered_content).css("fieldset.admin-held [data-action]").flat_map { |node| node["data-action"].split }
    assert_equal [ "input->admin--editor--code-limit#update" ], left, "the counter, which reads, is left in a held code card, and nothing else is"
  end

  # Plan ruling 10: a note's card held by someone else keeps its stored
  # kind checked and disables every button, the title is read-only with its
  # text, and its placeholder script reads only, so it is no action to keep.
  test "a note's card, rewritten; held by someone else its kind's buttons are disabled with the stored one checked, its title read-only, and no save is wired" do
    page = create_page(title: "Held note")
    block = page.content_blocks.new(block_type: "note", position: 0, settings: { "kind" => "warning" })
    block.assign_settings({ "title" => "Mind" }, locale: "en")
    block.save!
    as_owner { render_inline Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "en", editable: true) }
    assert_survives(rendered_content)

    reserve(block, page, users(:two), "tab-bbbbbbbb")
    as_viewer(users(:one), tab: "tab-aaaaaaaa") { render_inline Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: "en") }
    held = Nokogiri::HTML5.fragment(rendered_content)

    assert_equal [ "disabled" ] * 4, held.css("fieldset.admin-held input[type=radio]").map { |radio| radio["disabled"] }
    assert_equal [ "warning" ], held.css("input[type=radio][checked]").map { |radio| radio["value"] }
    assert_selector "fieldset.admin-held input[name='block[settings][title]'][readonly][value='Mind']"
    assert_no_selector "[data-controller~='admin--saving--autosave']"
    assert_empty held.css("fieldset.admin-held [data-action]").flat_map { |node| node["data-action"].split }.grep(/placeholder-from/),
      "the placeholder script listens without an action, so there is nothing of it to keep"
  end
end
