require "test_helper"

# `HeldFields` rewrites a rendered form once, on the server, instead of each of
# the eight field components learning a read-only option (plan "disagrees" 5,
# open point 7). The rewrite is proven here, per field kind, by comparing every
# element of the form before and after: nothing but the read-only attributes
# and the neutralised actions may differ.
class Admin::EditorScreen::HeldFieldsTest < ViewComponent::TestCase
  include ContentHelper
  include TestTypes

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

  test "an action that would write is taken off, one that only reads stays" do
    html = %(<button type="button" data-action="click->admin--ui--chip-input#remove keydown->admin--ui--chip-input#chipKeydown">x</button>
             <button type="button" data-action="admin--media--field#choose">choose</button>
             <div data-action="focusout->admin--rich-text--editor#containFocus media-picker:picked->admin--rich-text--editor#picked translate:use->admin--rich-text--editor#applySuggestion"></div>
             <button type="button" data-action="click->admin--editor--blocks#toggle">expand</button>
             <button type="button" data-action="admin--editing--hold#copy">copy</button>)

    page = Capybara.string(held(html))

    assert page.has_no_css?("[data-action*='chip-input'], [data-action*='media--field'], [data-action*='#picked'], [data-action*='applySuggestion']", visible: :all)
    assert page.has_css?("[data-action='focusout->admin--rich-text--editor#containFocus']", visible: :all)
    assert page.has_css?("[data-action='click->admin--editor--blocks#toggle']", visible: :all)
    assert page.has_css?("[data-action='admin--editing--hold#copy']", visible: :all)
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

  def comparable(node, ignore)
    attributes = node.attributes.transform_values(&:value).except(*ignore)
    if attributes["data-action"]
      kept = attributes["data-action"].split.grep_v(Admin::EditorScreen::HeldFields::NEUTRALISED)
      kept.empty? ? attributes.delete("data-action") : attributes["data-action"] = kept.join(" ")
    end
    attributes.sort.to_h
  end

  # Whether each of the eight field components survives the parse and the rewrite: a real
  # form, rendered editable, rewritten, compared control by control.
  def assert_survives(html)
    rewritten = held(html)
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

  test "Admin::Ui::ChipInputComponent and RelatedPostsComponent (a post's tags, a block's tag), rewritten" do
    post = create_post(title: "Chips", tags: [ "alpha", "beta" ])
    as_owner { render_inline Admin::EditorScreen::PostFormComponent.new(post: post, locale: "en") }

    assert_survives(rendered_content)
    assert_match(/chip-input/, rendered_content)
  end

  test "Admin::Columns::PlainColumnComponent and SlugColumnComponent (the page settings), rewritten" do
    page = create_page(title: "Plain and slug")
    as_owner { render_inline Admin::EditorScreen::PageSettingsFormComponent.new(page: page, locale: "en") }

    assert_selector "input[name='page[slug]']"
    assert_survives(rendered_content)
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
end
