require "application_system_test_case"

# The Search block on the public site, in a browser (search spec §7.2; the
# SiteSearch card): a plain GET form to the page itself, its results and
# pager drawn by the server, so a visitor searches and pages through with a
# script or without one; and at a phone's width the button stands under the
# field.
class SearchBlockSystemTest < ApplicationSystemTestCase
  BLOCK = ".content-block--search".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Help")
    place_search_block(@page)
    12.times { |n| create_page(title: format("Albatross %02d", n + 1)) }
  end

  def path = PublicSite::Urls.new.path_for(@page, "en")

  def box(selector) = page.evaluate_script("(() => { const r = document.querySelector(#{selector.to_json}).getBoundingClientRect(); return { top: r.top, bottom: r.bottom, left: r.left, width: r.width } })()")

  test "a visitor searches without a script and pages through the results" do
    visit path
    fill_in "Search this site", with: "albatross"
    press "Search"

    assert_selector "#{BLOCK} .search__summary[role=status]", text: "12 results for albatross"
    assert_selector "#{BLOCK} li.search__result", count: 10
    assert_equal "albatross", find_field("Search this site").value, "the field keeps the query"

    within("#{BLOCK} nav[aria-label='Pages of results']") { press "Next" }
    assert_selector "#{BLOCK} .search__summary", text: "12 results for albatross · Page 2"
    assert_selector "#{BLOCK} ol.search__results[start='11'] li.search__result", count: 2
    assert_selector "#{BLOCK} [aria-current=page]", text: "2"
    assert_includes page.current_url, "q=albatross&page=2"

    within("#{BLOCK} nav[aria-label='Pages of results']") { find("a[aria-label='Page 1']").click }
    assert_selector "#{BLOCK} .search__summary", text: "12 results for albatross"
    assert_no_selector "#{BLOCK} .search__summary", text: "Page"

    # The server draws the whole outcome: the address alone, as a browser
    # without a script follows a link, is the page past the end and its way
    # back.
    visit "#{path}?q=albatross&page=9"
    assert_selector "#{BLOCK} .search__message[role=status]", text: "12 results for albatross, but there is no page 9."
    press "Go to the first page"
    assert_selector "#{BLOCK} li.search__result", count: 10
  end

  test "at a phone's width the button stands under the field" do
    at_window(1400) do
      visit path
      field = box("#{BLOCK} .search__input")
      button = box("#{BLOCK} .search__button")
      assert_in_delta field["top"], button["top"], 1, "on a wide page the button stands beside the field"
      assert_operator button["left"], :>, field["left"] + field["width"] - 1
    end

    at_window(390, height: 844) do
      visit path
      field = box("#{BLOCK} .search__input")
      button = box("#{BLOCK} .search__button")
      assert_operator button["top"], :>=, field["bottom"], "the button is under the field"
      assert_in_delta field["width"], button["width"], 1, "and as wide"
      assert_equal 0, page.evaluate_script("document.documentElement.scrollWidth - document.documentElement.clientWidth"), "the page does not scroll sideways"
    end
  end
end
