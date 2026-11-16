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

  def item(title: "Publishing a page", url_path: "/guide/publishing", kind: :page, where: %w[Guide Editors], date: nil, snippet: nil, tags: [], close: false)
    SiteSearch::Shown::Item.new(kind: kind, record: nil, title: title, url_path: url_path, where: where, date: date,
      snippet: snippet || snippet("a page goes live when you press Publish", "live", "Publish"), tags: tags, close: close)
  end

  def answer(state, query: "publish", results: [], total: 0, page: 1, live_note: false, correction: nil, close_matches: false)
    SiteSearch::Answer.new(query: query, state: state, results: results, total: total,
      pagination: Pagination.new(page: page, per_page: SiteSearch::Answer::PER_PAGE, total: total), live_note: live_note,
      correction: correction, close_matches: close_matches)
  end

  # The component drawn for `answer`, to ask its private methods.
  def drawn(answer)
    component = Blocks::SearchComponent.new(block: search_block, page: @shown)
    vc_test_controller.search_answer = answer
    render_inline(component)
    component
  end

  def draw(answer, block: search_block)
    vc_test_controller.search_answer = answer
    render_inline(Blocks::SearchComponent.new(block: block, page: @shown))
  end

  def path = PublicSite::Urls.new.path_for(@shown, "en")

  # A post result found for its tags, under its date.
  def post_item(tags:)
    item(title: "Deploy previews for every pull request", url_path: "/blog/previews", kind: :post, where: nil,
      date: Time.zone.local(2026, 11, 12, 9), tags: tags)
  end

  def page_item = item

  # The page of results for `items`, as Nokogiri, for a query that found them exactly.
  def render_results(*items, query: "publish")
    draw(answer(:results, query: query, results: items, total: items.size))
  end

  # The results of a search with no exact hit: close matches, with the correction.
  def close_answer(query:, correction:)
    answer(:results, query: query, results: [ post_item(tags: %w[deployment]) ], total: 1, correction: correction, close_matches: true)
  end

  # A search that found nothing, with the correction.
  def none_answer(query:, correction:)
    answer(:none, query: query, correction: correction)
  end

  # `answer` drawn, its results replaced by `items` when given.
  def render_answer(answer, items: nil)
    answer = answer.with(results: items, total: items.size) if items
    draw(answer)
  end

  test "empty draws the field alone" do
    block = search_block
    draw(answer(:empty, query: nil), block: block)

    assert_selector "div.content-block.content-block--search form.search__form[role=search][method=get][action='#{path}']"
    input = page.find("input.search__input[type=search][name=q][maxlength='200']")
    assert_equal "", input.value.to_s
    assert_selector "label.search__label[for='#{input[:id]}']", text: "Search this site"
    assert_selector "button.search__button[type=submit]", text: "Search"
    assert_no_selector "ol"
    # No outcome's line: only the suggestions' live region, empty.
    assert_no_selector "[role=status]:not([data-search-suggest-target=status])"
    assert_no_selector ".search__note"
    assert_no_selector "input[type=hidden]", visible: :all
  end

  test "the form carries the suggestions' markup: the controller, its values, its targets and the option's template, all hidden until the script shows them" do
    block = search_block
    draw(answer(:empty, query: nil), block: block)

    form = page.find("form.search__form[data-controller='search-suggest']")
    assert_equal "Suggestions aren't available right now. Press Enter to search.", form["data-search-suggest-unavailable-value"]
    assert_selector ".search-suggest input.search__input[data-search-suggest-target=input]"
    assert_selector ".search-suggest__loading[data-search-suggest-target=loading][hidden]", text: "Looking…", visible: :all
    assert_selector ".search-suggest__list[data-search-suggest-target=popup][hidden] ul#search-#{block.id}-suggestions[data-search-suggest-target=listbox][aria-label='Suggestions']", visible: :all
    assert_selector ".search-suggest__list p.search-suggest__message[data-search-suggest-target=message][hidden]", visible: :all
    assert_selector "template[data-search-suggest-target=option]", visible: :all
    option = Nokogiri::HTML5.fragment(rendered_content).at_css("template[data-search-suggest-target=option]")
    assert_equal %w[label kind where], option.css("li.search-suggest__option [data-part]").map { it["data-part"] }
    assert_selector ".search__hidden[data-search-suggest-target=status][role=status][aria-live=polite]", visible: :all, text: ""
    assert_nil page.find("input.search__input")["role"], "the field is a combobox only with the script"
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

  test "a result's marks that are no Integer range within the text are left out before they are sorted, the words kept" do
    text = "albatross and walrus"
    marks = [ [ 14, 6 ], [ nil, 3 ], [ "0", 9 ], [ 0, nil ], [ 0, 9 ], [ -4, 2 ], [ 40, 3 ], [ 3, 0 ], [ 2.0, 3 ] ]
    result = Blocks::SearchComponent::Result.new(item(snippet: SiteSearch::Snippet.new(text: text, marks: marks)), words: [])

    assert_equal "<mark>albatross</mark> and <mark>walrus</mark>", result.snippet
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

  test "a tag is matched when a word of it begins with a query word of 3 or more, or equals a shorter one" do
    assert Blocks::SearchComponent.matched_tag?("deployments", %w[deploy])
    assert_not Blocks::SearchComponent.matched_tag?("running", %w[ran])
    assert Blocks::SearchComponent.matched_tag?("ci", %w[ci])
    assert_not Blocks::SearchComponent.matched_tag?("cicd", %w[ci])
    assert Blocks::SearchComponent.matched_tag?("Zero-Downtime deploys", %w[downtime]), "any word of the tag, folded to lower case"
    assert_not Blocks::SearchComponent.matched_tag?("deployments", [])
  end

  test "a result's tags are its item's, each matched by the query's words, and on close matches the correction's too" do
    results = [ item(kind: :post, where: nil, tags: %w[deployments previews kamal-proxy], close: true), item ]
    component = drawn(answer(:results, query: "Deploy", results: results, total: 2))
    post, page = component.send(:results)

    assert_equal [ Blocks::SearchComponent::Result::Tag.new(name: "deployments", matched: true),
                   Blocks::SearchComponent::Result::Tag.new(name: "previews", matched: false),
                   Blocks::SearchComponent::Result::Tag.new(name: "kamal-proxy", matched: false) ], post.tags
    assert_predicate post.tags.first, :matched?
    assert_predicate post, :close?
    assert_equal [], page.tags
    assert_not_predicate page, :close?

    close = drawn(answer(:results, query: "kamel proxi", results: results, total: 2, correction: "kamal proxy", close_matches: true))
    assert_equal [ false, false, true ], close.send(:results).first.tags.map(&:matched?)
    exact = drawn(answer(:results, query: "kamel proxi", results: results, total: 2, correction: "kamal proxy", close_matches: false))
    assert_equal [ false, false, false ], exact.send(:results).first.tags.map(&:matched?), "the correction's words count on close matches only"
  end

  test "close_matches?, correction and correction_path come from the answer" do
    component = drawn(answer(:results, query: "deplyment", results: [ item(close: true) ], total: 1, correction: "albatross & co", close_matches: true))

    assert component.send(:close_matches?)
    assert_equal "albatross & co", component.send(:correction)
    assert_equal "#{path}?q=albatross+%26+co", component.send(:correction_path)
    assert_nil component.send(:suggest_url)

    plain = drawn(answer(:results, query: "live", results: [ item ], total: 1))
    assert_not plain.send(:close_matches?)
    assert_nil plain.send(:correction)
    assert_nil plain.send(:correction_path)
  end

  test "string answers the new keys and no other" do
    component = drawn(answer(:empty, query: nil))
    values = { query: "q", correction: "c", page: 2, results: "r" }
    (Blocks::SearchComponent::STRINGS - %i[results suggestions]).each { |key| assert_kind_of String, component.send(:string, key, **values) }

    assert_equal "Tagged", component.send(:string, :tagged)
    assert_equal "matches your search", component.send(:string, :matched_tag)
    assert_equal "No exact matches for q. Close matches:", component.send(:string, :close_matches, query: "q")
    assert_equal "Did you mean c?", component.send(:string, :did_you_mean, correction: "c")
    assert_equal "6 suggestions", component.send(:string, :suggestions, count: 6)
    assert_equal "1 suggestion", component.send(:string, :suggestions, count: 1)
    assert_equal "Looking…", component.send(:string, :suggestions_loading)
    assert_equal %w[Page Post Tag], %i[kind_page kind_post kind_tag].map { |key| component.send(:string, key) }
    assert_raises(ArgumentError) { component.send(:string, :suggestions) }
    assert_raises(ArgumentError) { component.send(:string, :nope) }
  end

  test "a post result draws Tagged and its tags under the date, a matched tag in mark and in words" do
    html = render_results(post_item(tags: %w[deployment previews]), query: "deployment")
    line = html.at_css(".search__result .search__tags")
    assert_equal "Tagged", line.children.first.text.strip
    assert_equal "deployment", line.at_css("mark").text.sub(" (matches your search)", "")
    assert_equal " (matches your search)", line.at_css("mark .search__hidden").text
    assert line.previous_element.matches?(".search__where--date")
    assert_equal "Tagged deployment (matches your search), previews", line.text.squish, "the names comma-joined, plain text"
    assert_empty line.css("a"), "a tag is no link"
  end

  test "a page result draws no tags line" do
    assert_nil render_results(page_item).at_css(".search__tags")
  end

  test "close matches draw one status line above the results; Did you mean stands above it with an unprefetched link" do
    html = render_answer(close_answer(query: "deplyment", correction: "deployment"))
    correction, close = html.css(".search__correction, .search__close").to_a
    assert_equal "No exact matches for deplyment. Close matches:", close.text.squish
    assert_equal "deplyment", close.at_css("q").text, "the query in its q, whose quote marks are the stylesheet's"
    assert_equal "status", close["role"]
    assert_equal "false", correction.at_css("a")["data-turbo-prefetch"]
    assert_equal "#{path}?q=deployment", correction.at_css("a")["href"]
    assert_equal "Did you mean deployment?", correction.text.squish
    assert close.next_element.matches?("ol.search__results"), "the close line stands right above the results"
    assert_nil html.at_css(".search__summary"), "the close line stands in place of the count"
  end

  test "Did you mean alone stands above Nothing found" do
    html = render_answer(none_answer(query: "kamel proxi", correction: "kamal proxy"))
    assert html.at_css(".search__correction + .search__message")
    assert_equal "#{path}?q=kamal+proxy", html.at_css(".search__correction a")["href"]
  end

  test "a tag, a correction and a query like markup are escaped" do
    html = render_answer(close_answer(query: %(<b>x</b>), correction: %(<img src=x>)), items: [ post_item(tags: [ "<script>t</script>" ]) ])
    assert_empty html.css("b, img, script")
    assert_equal "<script>t</script>", html.at_css(".search__tags .search__tag").text
    assert_equal "Did you mean <img src=x>?", html.at_css(".search__correction").text.squish
    assert_equal "#{path}?q=%3Cimg+src%3Dx%3E", html.at_css(".search__correction a")["href"]
  end

  test "nothing in the component, its result or its template marks a string as safe" do
    sources = %w[app/components/blocks/search_component.rb app/components/blocks/search_component.html.erb
                 app/components/blocks/search_component/result.rb].map { |file| Rails.root.join(file).read.gsub(/<%#.*?%>/m, "").gsub(/^\s*#.*$/, "") }
    sources.each do |source|
      assert_no_match(/\braw\b|html_safe|<%==/, source)
    end
  end

  test "suggest_url is the suggestions' path on a site with a search page, and nil in the preview" do
    block = search_block
    publish_changes(@shown)
    vc_test_controller.search_answer = answer(:empty, query: nil)
    component = Blocks::SearchComponent.new(block: block, page: @shown)
    render_inline(component)
    assert_equal "/search/suggestions", component.send(:suggest_url)

    vc_test_controller.instance_variable_set(:@public_urls, PublicSite::Urls.new(preview: true))
    preview = Blocks::SearchComponent.new(block: block, page: @shown)
    vc_test_controller.search_answer = answer(:empty, query: nil, live_note: true)
    render_inline(preview)
    assert_nil preview.send(:suggest_url)
  end
end
