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
    [ "https://example.org/a?b=1", "http://example.org", "mailto:a@example.org", "/about", "#team" ].each do |address|
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

  # --- The image (#144) -------------------------------------------------

  def asset_with_alt(words = "Library words")
    create_media_asset(filename: "tiny.png").tap { |asset| asset.update!(alt: words) }
  end

  def imaged(settings = {}, asset: asset_with_alt, alt: nil, **words)
    block_with(settings, **words).tap do |block|
      block.media_asset = asset
      block.alt = alt if alt
    end
  end

  test "an image alone draws a card, an icon or a link alone still does not, and an image that is gone draws nothing" do
    draw imaged
    assert_selector ".content-block--card img[alt='Library words']", count: 1

    with_choices_theme do
      draw block_with({ "icon" => "brush", "link" => "/about" })
      assert_no_selector ".content-block--card"
    end

    gone = imaged(asset: create_media_asset.tap { |asset| asset.file.detach })
    draw gone
    assert_no_selector ".content-block--card"
  end

  test "the image stands above the icon and the title, one img with no wrapper, its size reserved and no ratio forced" do
    with_choices_theme do
      asset = asset_with_alt
      draw imaged({ "icon" => "brush" }, asset: asset, title: "T", text: "W")
      root = Nokogiri::HTML5.fragment(rendered_content).at_css(".content-block--card")
      assert_equal %w[img span h3 p], root.element_children.map(&:name)
      img = root.at_css("img")
      assert_equal [ asset.width.to_s, asset.height.to_s ], [ img["width"], img["height"] ]
      assert_includes img["class"], "content-block--card__image"
    end
  end

  test "one link per card: on the title, else on the text, else on the image, whose alt names it" do
    link = { "link" => "/about" }

    draw imaged(link, title: "T", text: "W")
    assert_selector "a", count: 1
    assert_selector "h3 a[href='/about']", text: "T"
    assert_no_selector "a img"

    draw imaged(link, text: "W")
    assert_selector "a", count: 1
    assert_selector "p a[href='/about']", text: "W"
    assert_no_selector "a img"

    draw imaged(link)
    assert_selector "a", count: 1
    assert_selector "a[href='/about'] img[alt='Library words']", count: 1

    draw imaged({ "link" => "javascript:alert(1)" })
    assert_no_selector "a"
    assert_selector "img", count: 1
  end

  test "the alt is the block's override, else the library's, and an image with neither has an empty alt" do
    draw imaged(alt: "My words")
    assert_selector "img[alt='My words']"

    draw imaged
    assert_selector "img[alt='Library words']"

    draw imaged(asset: asset_with_alt(""))
    assert_selector "img[alt='']"
  end

  test "image is nil without one, and otherwise the words the Image block's picture takes, in a column as wide as its column" do
    assert_nil Blocks::CardComponent.new(block: block_with(title: "T"), page: root_page).send(:image)

    asset = asset_with_alt
    image = Blocks::CardComponent.new(block: imaged(asset: asset), page: root_page).send(:image)
    assert_equal %i[alt asset sizes], image.keys.sort
    assert_equal [ asset, "Library words", Blocks::ImageComponent::SIZES ], image.values_at(:asset, :alt, :sizes)

    section = root_page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "two" })
    in_column = root_page.content_blocks.create!(block_type: "card", position: 0, section: section, section_column: 2, media_asset: asset)
    image = Blocks::CardComponent.new(block: in_column, page: root_page).send(:image)
    assert_equal Blocks::SectionComponent.image_sizes(section, 2), image[:sizes]
  end
end
