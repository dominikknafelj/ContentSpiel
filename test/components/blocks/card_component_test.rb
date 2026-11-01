require "test_helper"

class Blocks::CardComponentTest < ActiveSupport::TestCase
  include ComponentTestHelper
  include ThemeTestHelper

  def block_with(settings = {}, title: nil, text: nil, locale: "en")
    block = ContentBlock.new(owner: root_page, block_type: "card")
    block.assign_settings({ "title" => title, "text" => text }.compact.merge(settings), locale: locale)
    block
  end

  def draw(block) = render_inline(Blocks::CardComponent.new(block: block, page: root_page))

  test "a card is drawn with a title alone and with a text alone, and not with neither, an icon alone included" do
    with_choices_theme do
      draw block_with(title: "Only a title")
      assert_selector ".content-block--card h3", text: "Only a title"
      assert_no_selector ".content-block--card p"

      draw block_with(text: "Only a text")
      assert_selector ".content-block--card p", text: "Only a text"
      assert_no_selector ".content-block--card h3"

      draw block_with({ "icon" => "brush", "link" => "/about" })
      assert_no_selector ".content-block--card"
    end
  end

  test "the icon is inlined with aria-hidden and focusable false, and there is no icon element for an unknown or blank icon" do
    with_choices_theme do
      draw block_with({ "icon" => "brush" }, title: "T")
      assert_selector ".content-block--card__icon svg[aria-hidden=true][focusable=false]", count: 1
      assert_no_selector ".content-block--card img"

      draw block_with({ "icon" => "retired" }, title: "T")
      assert_no_selector ".content-block--card__icon"
      assert_no_selector ".content-block--card svg"

      draw block_with({ "icon" => "" }, title: "T")
      assert_no_selector ".content-block--card__icon"
    end
  end

  test "each accepted link is drawn as the link, and a stored value no longer accepted is drawn as no link" do
    [ "https://example.org/a?b=1", "http://example.org", "mailto:a@example.org", "/about" ].each do |address|
      draw block_with({ "link" => address }, title: "T")
      assert_selector "h3 a[href='#{address}']", text: "T"
    end

    [ "javascript:alert(1)", "//evil.example/x", "ftp://example.org", "about", "https://u:p@example.org" ].each do |address|
      block = block_with({}, title: "T")
      block.settings = block.settings.merge("link" => address) # written around the service
      draw block
      assert_selector ".content-block--card h3", text: "T"
      assert_no_selector "a"
    end
  end

  test "a title and a text that look like markup are text" do
    draw block_with({ "link" => "/a\"><script>x</script>" }, title: "<script>x</script>", text: "<b>y</b>")
    assert_no_selector "script", visible: :all
    assert_no_selector "b"
    assert_includes rendered_content, "&lt;script&gt;"
    assert_includes rendered_content, "&lt;b&gt;y&lt;/b&gt;"
  end

  test "a visitor of another language reads the title and text with the site's fallback" do
    block = block_with(title: "English title", text: "English text")
    block.assign_settings({ "title" => "Deutscher Titel" }, locale: "de")

    I18n.with_locale(:de) { draw block }
    assert_selector "h3", text: "Deutscher Titel"
    assert_selector "p", text: "English text"

    I18n.with_locale(:es) { draw block }
    assert_selector "h3", text: "English title"
  end

  test "a card with a link and a text but no title draws the link on the text, never drops it" do
    draw block_with({ "link" => "/about" }, text: "Only text")
    assert_selector "p a[href='/about']", text: "Only text"
    assert_no_selector "h3"
  end
end
