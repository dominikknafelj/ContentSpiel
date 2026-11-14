require "test_helper"

# `Blocks::SearchComponent` (search spec §7.2; the SiteSearch card): the
# field, and for a request with a query its outcome, drawn from the
# request's `search_answer`, which these tests hand in per state through a
# controller of their own. Everything it prints is escaped text but the
# snippet's marks, which are the component's own markup.
class Blocks::SearchComponentTest < ActiveSupport::TestCase
  include ComponentTestHelper

  # The previews' controller with an answer set by the test, as
  # `PublicPageRendering#search_answer` hands one to the view.
  class AnsweringController < ComponentPreviewsController
    attr_accessor :search_answer

    helper_method :search_answer
  end

  def vc_test_controller_class = AnsweringController

  XSS = %("><img src=x onerror=alert(1)>).freeze

  # `@page` is Capybara's (ViewComponent's test helpers keep the rendered
  # fragment there), so the page a block stands on is `@shown`.
  setup { @shown = create_page(title: "Guide") }

  def search_block(label: nil, page: @shown)
    settings = label ? { "label" => label } : {}
    result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "search", settings: settings })
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  def snippet(text, *words)
    marks = words.map { |word| [ text.index(word), word.length ] }
    SiteSearch::Snippet.new(text: text, marks: marks)
  end

  def item(title: "Publishing a page", url_path: "/guide/publishing", kind: :page, where: %w[Guide Editors], date: nil, snippet: nil)
    SiteSearch::Shown::Item.new(kind: kind, record: nil, title: title, url_path: url_path, where: where, date: date,
      snippet: snippet || snippet("a page goes live when you press Publish", "live", "Publish"))
  end

  def answer(state, query: "publish", results: [], total: 0, page: 1, live_note: false)
    SiteSearch::Answer.new(query: query, state: state, results: results, total: total,
      pagination: Pagination.new(page: page, per_page: SiteSearch::Answer::PER_PAGE, total: total), live_note: live_note)
  end

  def draw(answer, block: search_block)
    vc_test_controller.search_answer = answer
    render_inline(Blocks::SearchComponent.new(block: block, page: @shown))
  end

  def path = PublicSite::Urls.new.path_for(@shown, "en")

  test "empty draws the field alone" do
    block = search_block
    draw(answer(:empty, query: nil), block: block)

    assert_selector "div.content-block.content-block--search form.search__form[role=search][method=get][action='#{path}']"
    input = page.find("input.search__input[type=search][name=q][maxlength='200']")
    assert_equal "", input.value.to_s
    assert_selector "label.search__label[for='#{input[:id]}']", text: "Search this site"
    assert_selector "button.search__button[type=submit]", text: "Search"
    assert_no_selector "ol"
    assert_no_selector "[role=status]"
    assert_no_selector ".search__note"
    assert_no_selector "input[type=hidden]", visible: :all
  end

  test "results draw the count, the list starting at the first result's number and the snippet marked and escaped" do
    results = [ item(snippet: snippet("<b>x</b> live", "live")) ]
    draw(answer(:results, query: "live", results: results, total: 124, page: 6))

    assert_selector "p.search__summary[role=status]", text: "124 results for live · Page 6"
    assert_selector "p.search__summary q", text: "live"
    assert_selector "ol.search__results[start='51'] li.search__result", count: 1
    assert_selector "a.search__title[href='/guide/publishing']", text: "Publishing a page"
    snippet = page.find("p.search__snippet")
    assert_includes snippet.native.inner_html, "&lt;b&gt;x&lt;/b&gt; <mark>live</mark>"
    assert_no_selector ".search__snippet b"
    assert_equal "live", page.find("input[name=q]").value
  end

  test "one result says result, and the first page writes no start" do
    draw(answer(:results, query: "live", results: [ item ], total: 1))

    assert_selector "p.search__summary", text: "1 result for live"
    assert_no_selector "p.search__summary", text: "Page"
    assert_selector "ol.search__results:not([start])"
    assert_no_selector "nav"
  end

  test "a page shows its place, a post its date" do
    published = Time.zone.local(2026, 10, 28, 9)
    results = [ item, item(title: "0.5.0: the Diagram block", url_path: "/blog/diagram", kind: :post, where: nil, date: published) ]
    draw(answer(:results, results: results, total: 2))

    first, second = page.all("li.search__result").to_a
    assert_equal "Guide › Editors", first.find(".search__where").text
    assert_equal "28 Oct 2026", second.find(".search__where.search__where--date").text
    assert_equal Object.new.extend(ThemeHelper).post_date(Post.new(published_at: published)), second.find(".search__where").text,
      "the date is written as the site's post_date writes it"
  end

  test "the pager draws previous, first, the pages around, the last with gaps, next, and no prefetch" do
    draw(answer(:results, query: "page", results: [ item ], total: 124, page: 6))

    pager = page.find("nav.search-pager[aria-label='Pages of results']")
    links = pager.all("a").map { |link| [ link.text.strip, link[:href] ] }
    assert_equal [ [ "← Previous", "#{path}?q=page&page=5" ], [ "1", "#{path}?q=page&page=1" ], [ "5", "#{path}?q=page&page=5" ],
                   [ "7", "#{path}?q=page&page=7" ], [ "13", "#{path}?q=page&page=13" ], [ "Next →", "#{path}?q=page&page=7" ] ], links
    assert_equal "Page 5", pager.find("a[href$='page=5']:not([rel])")[:"aria-label"]
    assert_selector "nav.search-pager span[aria-current=page]", text: "6"
    assert_selector "nav.search-pager [aria-hidden=true]", text: "…", count: 2
    assert_equal "prev", pager.find("a", text: "Previous")[:rel]
    assert_equal "next", pager.find("a", text: "Next")[:rel]
    # A hovered page link would run a search (and count against the
    # visitor's limit) before anyone pressed it.
    assert_equal "false", pager[:"data-turbo-prefetch"]
    assert_empty pager.all("[data-turbo-prefetch]").to_a, "the nav says it for every link in it"
  end

  test "the first page draws no Previous and the last no Next" do
    draw(answer(:results, query: "page", results: [ item ], total: 30, page: 1))
    assert_no_selector "nav a", text: "Previous"
    assert_selector "nav a", text: "Next"

    draw(answer(:results, query: "page", results: [ item ], total: 30, page: 3))
    assert_selector "nav a", text: "Previous"
    assert_no_selector "nav a", text: "Next"
  end

  test "past the end says so and links to the first page" do
    draw(answer(:results, query: "page", results: [], total: 124, page: 99))

    assert_selector "p.search__message[role=status]", text: "124 results for page, but there is no page 99. Go to the first page"
    assert_selector "p.search__message q", text: "page"
    link = page.find("p.search__message a", text: "Go to the first page")
    assert_equal "#{path}?q=page&page=1", link[:href]
    assert_equal "false", link[:"data-turbo-prefetch"]
    assert_no_selector "ol"
    assert_no_selector "nav"
    assert_no_selector ".search__summary"
  end

  test "none, too long, limited and unavailable each say their sentence in role=status" do
    {
      answer(:none, query: "publsh") => "Nothing found for publsh. Check the spelling, or try fewer or other words.",
      answer(:too_long, query: "#{"how do I publish " * 13}a page") => "That search is too long. Use at most 200 characters.",
      answer(:limited) => "Too many searches. Please wait a minute, then try again.",
      answer(:unavailable) => "Search isn't available right now. Please try again later."
    }.each do |drawn, sentence|
      draw(drawn)

      assert_selector "p.search__message[role=status]", text: sentence, count: 1
      assert_equal drawn.query, page.find("input[name=q]").value, "#{drawn.state}: the field holds the text as typed"
      assert_no_selector "ol"
      assert_no_selector ".search__summary"
    end
    draw(answer(:none, query: "publsh"))
    assert_selector "p.search__message q", text: "publsh"
  end

  test "the preview's note stands above the outcome" do
    draw(answer(:results, results: [ item ], total: 1, live_note: true))

    note = page.find("p.search__note")
    assert_equal "Results come from the live site.", note.text
    assert page.has_css?("p.search__note + p.search__summary"), "the note stands between the field and the count"

    draw(answer(:none, live_note: true))
    assert page.has_css?("p.search__note + p.search__message")

    draw(answer(:none, live_note: false))
    assert_no_selector ".search__note"
  end

  test "a blank label draws the visitor's default in their language" do
    block = search_block(label: "Search the guide")
    draw(answer(:empty, query: nil), block: block)
    assert_selector "label", text: "Search the guide"

    I18n.with_locale(:de) { draw(answer(:empty, query: nil), block: block) }
    assert_selector "label", text: "Search the guide" # the editor's English, through the fallback

    I18n.with_locale(:de) { draw(answer(:empty, query: nil)) }
    assert_selector "label", text: "Search this site" # no German file: English, explicitly
  end

  test "two blocks on one page have their own field ids" do
    first = search_block
    second = search_block
    ids = [ first, second ].map do |block|
      draw(answer(:empty, query: nil), block: block)
      page.find("input[name=q]")[:id]
    end
    assert_equal 2, ids.uniq.size
  end

  test "a title, a place and a query that look like markup are text" do
    results = [ item(title: "<script>alert(1)</script>", where: [ "<i>Guide</i>", "Editors" ], snippet: snippet("before #{XSS} after", XSS)) ]
    draw(answer(:results, query: XSS, results: results, total: 1))

    html = rendered_content
    assert_no_selector "script", visible: :all
    assert_no_selector "img", visible: :all
    assert_no_selector ".search__where i"
    assert_selector "a.search__title", text: "<script>alert(1)</script>"
    assert_selector ".search__where", text: "<i>Guide</i> › Editors"
    assert_equal XSS, page.find("input[name=q]").value, "the field's value is the query, escaped in the attribute"
    assert_selector "p.search__summary q", text: XSS
    assert_includes html, "<mark>&quot;&gt;&lt;img src=x onerror=alert(1)&gt;</mark>"
    assert_not_includes html, "<img"
    assert_not_includes html, "<script"

    %i[none too_long limited unavailable].each do |state|
      draw(answer(state, query: XSS))
      assert_not_includes rendered_content, "<img", state.to_s
    end
    draw(answer(:results, query: XSS, results: [], total: 3, page: 9))
    assert_not_includes rendered_content, "<img", "past the end"
  end

  # The words are the component's own, and nothing else: a key a theme's
  # author mistyped is never I18n's "Translation missing" on a page.
  test "string answers its words and nothing else, and the count with the query marked" do
    component = Blocks::SearchComponent.new(block: search_block, page: @shown)
    vc_test_controller.search_answer = answer(:empty, query: nil)
    render_inline(component)

    assert_equal "Search", component.send(:string, :button)
    assert_equal "That search is too long. Use at most 200 characters.", component.send(:string, :too_long)
    error = assert_raises(ArgumentError) { component.send(:string, :copy) }
    assert_includes error.message, ":button"
    error = assert_raises(ArgumentError) { component.send(:string, :results, query: "x") }
    assert_includes error.message, "count:"
    marked = component.send(:string, :results, count: 2, query: ActionController::Base.helpers.tag.q("<b>"))
    assert_equal "2 results for <q>&lt;b&gt;</q>", marked
    assert_predicate marked, :html_safe?
    assert_equal "2 results for &lt;b&gt;", ERB::Util.html_escape(component.send(:string, :results, count: 2, query: "<b>")),
      "a plain string handed in is escaped where it is printed"
  end

  test "nothing in the component, its result or its template marks a string as safe" do
    sources = %w[app/components/blocks/search_component.rb app/components/blocks/search_component.html.erb
                 app/components/blocks/search_component/result.rb].map { |file| Rails.root.join(file).read.gsub(/<%#.*?%>/m, "").gsub(/^\s*#.*$/, "") }
    sources.each do |source|
      assert_no_match(/\braw\b|html_safe|<%==/, source)
    end
  end
end
