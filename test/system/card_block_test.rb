require "application_system_test_case"

# The Card block on the public site, as the browser computes it (theme
# choices spec): its ground, frame, icon, title and text are the tokens'
# values in both schemes, on the page, in a tinted band and in a strong band.
class CardBlockSystemTest < ApplicationSystemTestCase
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Cards")
  end

  def add_card(background: nil)
    attributes = { block_type: "card", settings: { "link" => "/about", "title" => "Card title en", "text" => "Card text en" } }
    if background
      section = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "section", settings: { "layout" => "one", "background" => background } }).record
      attributes.merge!(section_id: section.id, section_column: 1)
    end
    result = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: attributes)
    assert result.ok?, result.errors.to_sentence
  end

  def open_page
    publish_changes(@page)
    visit PublicSite::Urls.new.path_for(@page, "en")
    assert_selector ".content-block--card"
  end

  def with_theme(theme)
    page.execute_script("document.documentElement.dataset.theme = arguments[0]", theme)
    yield
  ensure
    page.execute_script("document.documentElement.dataset.theme = 'light'")
  end

  # What the card is drawn in, and what its tokens are THERE: probe spans go
  # inside the card, so a band's values are what they read. The sample has no
  # icon, so the probe wears the icon's class.
  def probe(index)
    page.evaluate_script(<<~JS, index)
      (() => {
        const card = document.querySelectorAll(".content-block--card")[arguments[0]]
        const token = (name, property = "color") => { const span = document.createElement("span"); span.style[property] = `var(${name})`; card.append(span); const value = getComputedStyle(span)[property]; span.remove(); return value }
        const icon = document.createElement("span"); icon.className = "content-block--card__icon"; card.append(icon)
        const iconColour = getComputedStyle(icon).color; icon.remove()
        const style = getComputedStyle(card)
        return {
          ground: style.backgroundColor, groundToken: token("--th-card-ground", "backgroundColor"),
          frame: [style.borderTopWidth, style.borderTopColor], line: token("--th-card-line"),
          icon: iconColour, iconToken: token("--th-card-icon"),
          title: getComputedStyle(card.querySelector(".content-block--card__title")).color, ink: token("--th-ink"),
          text: getComputedStyle(card.querySelector(".content-block--card__text")).color, dim: token("--th-dim"),
          bandInk: token("--th-on-band-strong"), band: token("--th-band-strong", "backgroundColor")
        }
      })()
    JS
  end

  def assert_tokens(found, where)
    assert_equal found["groundToken"], found["ground"], "#{where}: ground"
    assert_equal [ "1px", found["line"] ], found["frame"], "#{where}: frame"
    assert_equal found["iconToken"], found["icon"], "#{where}: icon"
    assert_equal found["ink"], found["title"], "#{where}: title"
    assert_equal found["dim"], found["text"], "#{where}: text"
  end

  test "a card is drawn in its three tokens, its title in the ink and its text in the dim, in both schemes" do
    add_card
    open_page

    seen = %w[light dark].to_h do |theme|
      with_theme(theme) do
        found = probe(0)
        assert_tokens(found, theme)
        [ theme, found ]
      end
    end
    %w[ground line icon ink dim].each do |part|
      assert_not_equal seen["light"][part], seen["dark"][part], "#{part} differs between light and dark"
    end
  end

  test "in a tinted band a card keeps its tokens, and in a strong band they are the band's, in both schemes" do
    add_card
    add_card(background: "tinted")
    add_card(background: "strong")
    open_page
    assert_selector ".content-section--strong .content-block--card", count: 1

    %w[light dark].each do |theme|
      with_theme(theme) do
        plain, tinted, strong = (0..2).map { |index| probe(index) }
        assert_tokens(tinted, "#{theme}, tinted band")
        assert_equal plain["ground"], tinted["ground"], "#{theme}: a tinted band leaves the card's ground"
        assert_tokens(strong, "#{theme}, strong band")
        assert_not_equal plain["ground"], strong["ground"], "#{theme}: the strong band's ground is its own"
        assert_equal strong["bandInk"], strong["title"], "#{theme}: the title is the band's text"
        assert_not_equal strong["band"], strong["ground"], "#{theme}: the card stands off the band"
      end
    end
  end
end
