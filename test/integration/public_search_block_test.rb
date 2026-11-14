require "test_helper"

# The Search block on a published page, through the request (search spec
# §7.1, §7.2): its field points at the page itself, a search runs once
# however many blocks the page holds, and what it finds is drawn with the
# address a visitor follows.
class PublicSearchBlockTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Help")
  end

  def path = PublicSite::Urls.new.path_for(@page, "en")

  def section_on(page)
    result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "section", settings: { "layout" => "two" } })
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def blocks_drawn = Nokogiri::HTML5(response.body).css(SearchBlock::BLOCK).map { |block| search_drawn(block.to_html) }

  test "two Search blocks, one in a column, search once and draw the same answer" do
    place_search_block(@page)
    place_search_block(@page, section: section_on(@page))
    create_page(title: "Albatross")
    create_page(title: "Albatross nest")

    calls = 0
    search = SiteSearch.method(:search)
    with_singleton_override(SiteSearch, :search, ->(query) { calls += 1; search.call(query) }) do
      get path, params: { q: "albatross" }
    end

    assert_response :success
    assert_equal 1, calls, "one search for the request"
    drawn = blocks_drawn
    assert_equal 2, drawn.size, "both blocks are drawn"
    assert_equal drawn.first, drawn.last
    assert_equal "results", drawn.first[:state]
    summaries = Nokogiri::HTML5(response.body).css(".search__summary").map(&:text)
    assert_equal [ "2 results for albatross" ] * 2, summaries
    assert_equal 2, Nokogiri::HTML5(response.body).css("form[role=search][action='#{path}']").size, "each field searches the page it stands on"
  end

  test "a page with a Search block and no query searches nothing and is public" do
    place_search_block(@page)

    with_singleton_override(SiteSearch, :search, ->(*) { flunk "a page view asked the backend" }) do
      get path
    end
    assert_response :success
    assert_equal "empty", search_drawn[:state]
    assert_equal "max-age=0, public, must-revalidate", response.headers["Cache-Control"]
  end

  test "a search finds the canary-free result and draws it with its address" do
    place_search_block(@page)
    found = create_page(title: "Albatross", parent: @page)
    assert ContentBlocks::Save.call(ContentBlock.new(owner: found), attributes: { block_type: "rich_text" },
      translations: { "en" => { body: { "type" => "doc", "content" => [ { "type" => "paragraph",
        "content" => [ { "type" => "text", "text" => "Where the albatross nests & sleeps, \"<i>\" < 2 cliffs" } ] } ] } } }).ok?
    publish_changes(found)

    get path, params: { q: "albatross" }

    assert_response :success
    assert_equal [ [ "Albatross", PublicSite::Urls.new.path_for(found, "en") ] ], search_drawn[:results]
    html = Nokogiri::HTML5(response.body)
    assert_equal [ root_page.title, "Help" ].join(" › "), html.at_css(".search__where").text, "the page's place: the pages above it"
    snippet = html.at_css(".search__snippet")
    assert snippet.at_css("mark"), "the match is marked"
    # Postgres' headline leaves a tag-like word (`<i>`) out of a snippet;
    # the markup characters around it are text.
    assert_includes snippet.text, "nests & sleeps", "text with markup characters is text"
    assert_includes snippet.text, "< 2 cliffs"
    assert_equal [ "mark" ], snippet.element_children.map(&:name).uniq
    assert_equal "albatross", html.at_css("input[name=q]")["value"]
  end
end
