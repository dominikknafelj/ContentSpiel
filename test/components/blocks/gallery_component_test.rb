require "test_helper"

class Blocks::GalleryComponentTest < ActiveSupport::TestCase
  include ComponentTestHelper

  # `count` library images, each titled by its position, with the library's
  # own alt "Library alt <n>" in English.
  def images(count)
    Array.new(count) do |index|
      asset = create_media_asset
      asset.update!(title: "Image #{index + 1}", alt: "Library alt #{index + 1}")
      asset
    end
  end

  def gallery(assets, layout: "grid", texts: {}, label: nil, settings: {}, page: root_page, **block_attributes)
    block = ContentBlock.new(owner: page, block_type: "gallery", **block_attributes)
    ids = assets.map { |asset| asset.is_a?(Integer) ? asset : asset.id }
    block.assign_settings({ "layout" => layout, "images" => ids, "label" => label, "texts" => texts }.compact.merge(settings), locale: "en")
    block
  end

  def component(block) = Blocks::GalleryComponent.new(block: block, page: root_page)

  def draw(block) = render_inline(component(block))

  test "a grid draws a named list of figures in order, each image through the picture component with its caption" do
    one, two, three = images(3)
    draw gallery([ two, one, three ], label: "Harbour walk", texts: { two.id.to_s => { "caption" => "The pier" } })

    assert_selector ".content-block--gallery.content-block--gallery--grid"
    assert_selector "ul.content-block--gallery__grid[aria-label='Harbour walk']"
    assert_selector "li.content-block--gallery__item figure", count: 3
    assert_equal [ "Library alt 2", "Library alt 1", "Library alt 3" ], page.all("li figure .content-block--gallery__frame img").map { |img| img[:alt] }
    assert_selector "li:first-child figcaption.content-block--gallery__caption", text: "The pier"
    assert_selector "figcaption", count: 1
    assert_no_selector "[data-controller]"
    assert_no_selector "[tabindex]"
  end

  test "a grid with no label is named by the visitor's word" do
    draw gallery(images(1))
    assert_selector "ul.content-block--gallery__grid[aria-label='Image gallery']"
  end

  test "a carousel draws the APG roles and names, the controls hidden, the track focusable and named" do
    assets = images(3)
    block = gallery(assets, layout: "carousel", label: "Harbour walk")
    block.id = 41
    draw block

    assert_selector "section.content-block--gallery.content-block--gallery--carousel[aria-roledescription='carousel'][aria-label='Harbour walk'][data-controller='gallery-carousel']"

    controls = page.find(".content-block--gallery__controls[data-gallery-carousel-target='controls']", visible: :all)
    assert controls[:hidden], "the controls are hidden until the script shows them"
    previous = controls.find("button.content-block--gallery__button--previous", visible: :all)
    following = controls.find("button.content-block--gallery__button--next", visible: :all)
    assert_equal [ "Previous image", "Next image" ], [ previous[:"aria-label"], following[:"aria-label"] ]
    assert_equal %w[gallery-41-track gallery-41-track], [ previous[:"aria-controls"], following[:"aria-controls"] ]
    assert_equal %w[previous next], [ previous[:"data-gallery-carousel-target"], following[:"data-gallery-carousel-target"] ]
    assert_equal %w[button button], [ previous[:type], following[:type] ]

    track = page.find("#gallery-41-track.content-block--gallery__track")
    assert_equal [ "0", "Images", "track" ], [ track[:tabindex], track[:"aria-label"], track[:"data-gallery-carousel-target"] ]
    slides = track.all(".content-block--gallery__slide")
    assert_equal [ "1 of 3", "2 of 3", "3 of 3" ], slides.map { |slide| slide[:"aria-label"] }
    slides.each do |slide|
      assert_equal [ "group", "slide", "slide" ], [ slide[:role], slide[:"aria-roledescription"], slide[:"data-gallery-carousel-target"] ]
      assert slide.has_selector?(".content-block--gallery__frame img", visible: :all)
      assert slide.has_no_selector?("a, button, [tabindex]", visible: :all), "a slide holds nothing focusable"
    end

    foot = page.find(".content-block--gallery__foot", visible: :all)
    assert foot[:hidden], "the foot is hidden until the script shows it"
    picks = foot.find(".content-block--gallery__picks", visible: :all)
    assert picks[:hidden], "the picker is hidden until the script shows it"
    buttons = picks.all("button.content-block--gallery__pick[data-gallery-carousel-target='pick']", visible: :all)
    assert_equal [ "Show image 1", "Show image 2", "Show image 3" ], buttons.map { |button| button[:"aria-label"] }
    assert_equal %w[1 2 3], buttons.map { |button| button[:"data-gallery-carousel-index-param"] }
    assert_equal [ "true", nil, nil ], buttons.map { |button| button[:"aria-current"] }
    position = foot.find(".content-block--gallery__position[data-gallery-carousel-target='position']", visible: :all)
    assert_equal "1 of 3", position.text(:all).strip

    status = page.find(".content-block--gallery__status[data-gallery-carousel-target='status']", visible: :all)
    assert status[:hidden], "the status is hidden until the script shows it"
    assert_equal [ "polite", "" ], [ status[:"aria-live"], status.text(:all).strip ]
  end

  test "one image draws a slide alone, and thirteen draw the position and no picker" do
    draw gallery(images(1), layout: "carousel", label: "Alone")
    assert_selector ".content-block--gallery--carousel figure.content-block--gallery__slide .content-block--gallery__frame img"
    assert_no_selector "[data-controller]"
    assert_no_selector "[aria-roledescription]", visible: :all
    assert_no_selector ".content-block--gallery__controls, .content-block--gallery__foot, .content-block--gallery__status, button, [tabindex]", visible: :all

    draw gallery(images(13), layout: "carousel")
    assert_selector "[data-controller='gallery-carousel']"
    assert_selector ".content-block--gallery__slide", count: 13
    assert_selector ".content-block--gallery__button", count: 2, visible: :all
    assert_selector ".content-block--gallery__position", text: "1 of 13", visible: :all
    assert_no_selector ".content-block--gallery__picks, .content-block--gallery__pick", visible: :all
  end

  test "twelve images still draw the picker" do
    draw gallery(images(BlockTypes::Gallery::PICKER_MAX), layout: "carousel")
    assert_selector ".content-block--gallery__pick", count: 12, visible: :all
  end

  test "an id that names no image is skipped and the positions count what is drawn" do
    one, two = images(2)
    block = gallery([ one, 2_000_000_000, two ], layout: "carousel", texts: { two.id.to_s => { "caption" => "Second drawn" } })
    component = component(block)
    render_inline component

    assert_equal [ 1, 2 ], component.send(:items).map(&:index)
    assert_equal [ "1 of 2", "2 of 2" ], page.all(".content-block--gallery__slide").map { |slide| slide[:"aria-label"] }
    assert_selector ".content-block--gallery__slide:nth-child(2) figcaption", text: "Second drawn"
    assert_selector ".content-block--gallery__position", text: "1 of 2", visible: :all
    assert_selector ".content-block--gallery__pick", count: 2, visible: :all

    draw gallery([ 2_000_000_000 ], layout: "carousel")
    assert_no_selector ".content-block--gallery", visible: :all
  end

  test "a language without texts falls back for the caption and takes the library's alt in its own language" do
    one, two = images(2)
    Mobility.with_locale(:de) { one.update!(alt: "Bibliothek eins") }
    block = gallery([ one, two ], texts: { one.id.to_s => { "caption" => "English caption", "alt" => "English alt" },
                                           two.id.to_s => { "alt" => "English second alt" } })
    block.assign_settings({ "texts" => { two.id.to_s => { "caption" => "Deutsch zwei" } } }, locale: "de")

    I18n.with_locale(:de) { draw block }
    assert_equal [ "Bibliothek eins", "English second alt" ], page.all("img").map { |img| img[:alt] },
      "the library's own German alt beats an English override; with no German alt anywhere, the English override"
    assert_equal [ "English caption", "Deutsch zwei" ], page.all("figcaption").map(&:text)

    I18n.with_locale(:es) { draw block }
    assert_equal [ "English alt", "English second alt" ], page.all("img").map { |img| img[:alt] }
    assert_equal [ "English caption", "Deutsch zwei" ], page.all("figcaption").map(&:text), "es falls back through the site's chain: en, then de"
  end

  test "a caption and a label that look like markup are text" do
    asset = images(1).first
    draw gallery([ asset ], label: %(<b onclick="x">Name</b>), texts: { asset.id.to_s => { "caption" => %(<script>alert(1)</script><i>Caption</i>) } })

    assert_selector "ul[aria-label='<b onclick=\"x\">Name</b>']"
    assert_selector "figcaption", text: "<script>alert(1)</script><i>Caption</i>"
    assert_no_selector "script, b, i", visible: :all
  end

  test "nothing is drawn for an empty gallery" do
    draw gallery([])
    assert_no_selector ".content-block--gallery", visible: :all
    assert_equal false, component(ContentBlock.new(owner: root_page, block_type: "gallery")).render?
  end

  test "every frame carries its ratio class and the fit class when set" do
    assets = images(2)
    { "3:2" => "3-2", "4:3" => "4-3", "1:1" => "1-1", "16:9" => "16-9" }.each do |ratio, suffix|
      draw gallery(assets, settings: { "ratio" => ratio })
      assert_selector ".content-block--gallery.content-block--gallery--ratio-#{suffix}"
      assert_no_selector ".content-block--gallery--fit"
    end

    draw gallery(assets, layout: "carousel", settings: { "ratio" => "16:9", "fit" => true })
    assert_selector ".content-block--gallery--carousel.content-block--gallery--ratio-16-9.content-block--gallery--fit"

    block = gallery(assets)
    block.settings = block.settings.merge("ratio" => "7:5", "layout" => "slideshow") # written around the service
    draw block
    assert_selector ".content-block--gallery--grid.content-block--gallery--ratio-3-2"
  end

  test "sizes divides each width by the images a row holds there, and never under-asks" do
    columns = Blocks::GalleryComponent::GRID_COLUMNS
    top = component(gallery(images(1)))
    assert_equal "(min-width: 768px) 236px, 100vw", top.send(:sizes, per_row: columns)
    assert_equal Blocks::ImageComponent::SIZES, top.send(:sizes, per_row: 1)
    assert_equal Blocks::ImageComponent::SIZES, top.send(:sizes)
    assert_equal "(min-width: 768px) 361px, 50vw", top.send(:sizes, per_row: 2), "an Integer is every width's count"

    page = create_page(title: "Columns")
    section = page.content_blocks.create!(block_type: :section, position: 0, settings: { "layout" => "two" })
    in_column = gallery(images(1), page: page, section: section, section_column: 1)
    column = Blocks::GalleryComponent.new(block: in_column, page: page)
    assert_equal "(min-width: 768px) 177px, (min-width: 480px) 50vw, 100vw", column.send(:sizes, per_row: columns)
    assert_equal Blocks::ImageComponent.sizes_for(in_column), column.send(:sizes, per_row: 1)

    # Each width asks at least what its row draws: three 236px images and
    # two gaps fill the 736px top-level block, two 177px images and a gap
    # the 368px column, and below 768px a phone's one column is the
    # viewport's width.
    assert_operator 3 * 236 + 2 * 14, :>=, Blocks::SectionComponent::CONTENT_WIDTH
    assert_operator 2 * 177 + 14, :>=, 368

    grid = component(gallery(images(2)))
    render_inline grid
    assert_equal [ grid.send(:sizes, per_row: columns) ], grid.send(:items).map { |item| item.picture[:sizes] }.uniq
    carousel = component(gallery(images(2), layout: "carousel"))
    render_inline carousel
    assert_equal [ carousel.send(:sizes, per_row: 1) ], carousel.send(:items).map { |item| item.picture[:sizes] }.uniq
  end

  test "the script's position and moved values are the uninterpolated patterns" do
    draw gallery(images(2), layout: "carousel")
    carousel = page.find("[data-controller='gallery-carousel']")
    assert_equal "%{index} of %{count}", carousel[:"data-gallery-carousel-position-value"]
    assert_equal "Image %{index} of %{count}", carousel[:"data-gallery-carousel-moved-value"]

    component = component(gallery(images(1)))
    render_inline component
    assert_equal "Image %{index} of %{count}", component.send(:pattern, :moved)
    assert_raises(ArgumentError) { component.send(:pattern, :label) }
    assert_raises(ArgumentError) { component.send(:string, :nothing) }
  end

  test "the words are the visitor's language's, English where it has none" do
    component = component(gallery(images(1)))
    render_inline component
    I18n.with_locale(:de) do
      words = [ component.send(:string, :label), component.send(:string, :carousel), component.send(:string, :slide),
                component.send(:string, :position, index: 3, count: 12), component.send(:string, :track), component.send(:string, :previous),
                component.send(:string, :next), component.send(:string, :show, index: 3), component.send(:string, :moved, index: 3, count: 12) ]
      assert_equal [ "Image gallery", "carousel", "slide", "3 of 12", "Images", "Previous image", "Next image", "Show image 3", "Image 3 of 12" ], words
    end
  end
end
