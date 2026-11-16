require "application_system_test_case"

# The Search block's suggestions while typing, in a browser (search 2 spec
# §4.5; the SiteSearchSuggest card): `search-suggest` turns the field into
# an ARIA 1.2 combobox, asks `POST /search/suggestions` 150 ms after the last
# key from two characters, draws the answer as text, walks it with the keys
# and the pointer, and takes all of it back before Turbo copies the page.
# Without the script the form is the plain GET it always was.
#
# The requests are watched and held through Cuprite's network domain:
# `count_requests_to` reads the traffic, `delay_answers_for` and
# `answer_suggestions_with` pause the suggestion requests (`Fetch` interception)
# and continue or answer them, and `with_script_blocked` aborts one module's request.
class SearchSuggestionsSystemTest < ApplicationSystemTestCase
  FORM = ".content-block--search form[role=search]".freeze
  SUGGESTIONS = %r{/search/suggestions\z}

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    SiteSearch::SuggestLimit.store.clear
    @page = create_page(title: "Help")
    place_search_block(@page)
    @page_path = PublicSite::Urls.new.path_for(@page, "en")
    @albatross_path = PublicSite::Urls.new.path_for(create_page(title: "Albatross"), "en")
    create_page(title: "<img src=x onerror=alert(1)> Albatross")
    create_post(title: "Algae", tags: %w[albatross-watch])
    # A post has an address only under a page that lists it.
    blog = create_page(title: "Blog")
    listing = ContentBlocks::Save.call(ContentBlock.new(owner: blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } })
    assert listing.ok?, listing.errors.to_sentence
    publish_changes(blog)
    open_page
  end

  test "the combobox's roles are written at connect and taken back before Turbo caches the page" do
    field = find("input[type=search]")
    assert_equal [ "combobox", "list", "false", "off" ], %w[role aria-autocomplete aria-expanded autocomplete].map { field[it] }
    assert_equal field["aria-controls"], find("[data-search-suggest-target=listbox]", visible: :all)["id"]
    assert_equal "listbox", find("[data-search-suggest-target=listbox]", visible: :all)["role"]
    page.execute_script("document.dispatchEvent(new Event('turbo:before-cache'))")
    %w[role aria-autocomplete aria-expanded aria-controls autocomplete].each { |name| assert_not attribute?(field, name), "#{name} is taken back" }
    assert_not attribute?(find("[data-search-suggest-target=listbox]", visible: :all), "role")

    # A page that is not left (an anchor of it) keeps its script: the
    # field is a combobox again the moment it is used.
    field.send_keys("alba")
    assert_equal "combobox", field["role"]
    assert_selector "[role=option]", text: "Albatross"
  end

  test "Down opens the list and walks it with the caret in the field; Enter goes; Escape closes; Tab chooses nothing" do
    field = type_in("alba")
    field.send_keys(:down)
    assert_equal "true", find("[role=option]", match: :first)["aria-selected"]
    assert_equal find("[role=option]", match: :first)["id"], field["aria-activedescendant"]
    assert_equal page.active_element, field
    field.send_keys(:escape)
    assert_equal "false", field["aria-expanded"]
    assert_nil field["aria-activedescendant"]
    assert_equal "alba", field.value, "Escape on an open list closes it and leaves the text"
    field.send_keys(:down, :tab)
    assert_equal "false", field["aria-expanded"]
    assert_current_path(@page_path)
    type_in("alba").send_keys(:down, :enter)
    assert_current_path(@albatross_path)
  end

  test "Up from the field goes to the last option, and Down past the last comes round to the first" do
    field = type_in("alba")
    options = find_all("[role=option]")
    field.send_keys(:up)
    assert_equal options.last["id"], field["aria-activedescendant"]
    field.send_keys(:down)
    assert_equal options.first["id"], field["aria-activedescendant"]
    assert_equal [ "true" ] + [ "false" ] * (options.size - 1), options.map { it["aria-selected"] }
  end

  test "Enter with no active option sends the form" do
    type_in("alba").send_keys(:enter)
    assert_current_path(/\?q=alba/)
  end

  test "the pointer over an option makes it active, a press goes to it, and the field keeps its focus" do
    field = type_in("alba")
    option = find("[role=option]", match: :first)
    option.hover
    assert_equal "true", option["aria-selected"]
    assert_equal page.active_element, field
    option.click
    assert_current_path(@albatross_path)
  end

  test "a press outside closes the list" do
    field = type_in("alba")
    find(".content-block--search .search__label").click
    assert_equal "false", field["aria-expanded"]
    assert_no_selector "[role=option]"
  end

  test "the focus leaving the field closes the list" do
    field = type_in("alba")
    page.execute_script("document.querySelector('.search__button').focus()")
    assert_equal "false", field["aria-expanded"]
    assert_no_selector "[role=option]"
  end

  test "no request under 2 characters, and one request per pause" do
    requests = count_requests_to(SUGGESTIONS) do
      type_in("a")
      sleep 0.3 # sleep: past the 150 ms debounce, so a request for one character would have been sent
      type_in("lbat", clear: false)
      sleep 0.3 # sleep: past the 150 ms debounce again, so a second request would have been sent
    end
    assert_equal 1, requests
  end

  test "a stale answer is dropped" do
    delay_answers_for("al", by: 0.6) do
      type_in("al", answered: false)
      sleep 0.2 # sleep: past the 150 ms debounce, so the request for "al" is sent and held
      type_in("bat", clear: false)
    end
    wait_for_state("open")
    assert_selector "[role=option]", text: "Albatross"
    assert_no_text "Algae"

    # The stale prefix's own answer does hold it.
    type_in("al")
    assert_selector "[role=option]", text: "Algae"
  end

  test "a title like markup is drawn as text in the listbox, and the typed prefix is marked" do
    type_in("albat")
    assert_selector "[role=option]", text: "<img src=x onerror=alert(1)>"
    assert_no_selector "[role=option] img"
    assert_equal "Albat", find("[role=option]", text: "Albatross", match: :first).find("mark").text
  end

  test "each option says its kind in words, and a tag is ruled off from the titles" do
    type_in("alba")
    assert_equal %w[Page Page Tag], find_all("[role=option] [data-part=kind]").map(&:text)
    tag = find("[role=option]", text: "albatross-watch")
    assert_includes tag[:class].split, "search-suggest__option--first-tag"
  end

  test "no suggestions, unavailable and limited draw the card's message row, and the live region says the server's sentence" do
    field = type_in("zzzz")
    assert_selector ".search-suggest__message", text: "No suggestions. Press Enter to search."
    assert_equal "No suggestions. Press Enter to search.", status_text
    assert_equal "false", field["aria-expanded"], "a message row is no option"
    assert_equal "empty", state

    answer_suggestions_with({ state: "refused", status: "", suggestions: [] }, status: 403) { type_in("zzzy") }
    assert_selector ".search-suggest__message", text: "Suggestions aren't available right now. Press Enter to search."
    assert_equal "Suggestions aren't available right now. Press Enter to search.", status_text
    assert_equal "unavailable", state

    limited = { state: "limited", status: "Too many suggestions asked. Press Enter to search.", suggestions: [] }
    answer_suggestions_with(limited, status: 429) { type_in("zzzx") }
    assert_selector ".search-suggest__message", text: "Too many suggestions asked. Press Enter to search."
    assert_equal "limited", state

    # Nothing is asked for a minute after limited, and the form still sends.
    requests = count_requests_to(SUGGESTIONS) do
      type_in("alba", answered: false)
      sleep 0.3 # sleep: past the 150 ms debounce, so a request would have been sent
    end
    assert_equal 0, requests
    field.send_keys(:enter)
    assert_current_path(/\?q=alba/)
  end

  # The endpoint never answers such an address; a script that drew one would
  # follow it on Enter or a press, so it is left out of the list.
  test "a suggestion whose address is another site's, a script's or does not parse is not drawn" do
    item = ->(label, url) { { kind: "page", kind_label: "Page", label: label, where: nil, url: url, marks: [] } }
    answer = { state: "ok", status: "1 suggestion",
               suggestions: [ item.("Elsewhere", "https://evil.example/x"), item.("Scripted", "javascript:alert(1)"),
                              item.("Unparsed", "http://["), item.("Albatross", @albatross_path) ] }
    answer_suggestions_with(answer, status: 200) { type_in("zzzz") }

    assert_equal [ "Albatross" ], find_all("[role=option] [data-part=label]").map(&:text)
    assert_equal "1 suggestion", status_text
    assert_equal find_all("[role=option]").size, status_text[/\d+/].to_i, "the count announced is the options drawn"
    find("input[type=search]").send_keys(:down, :enter)
    assert_current_path(@albatross_path)
  end

  test "the live region says only the answer that is drawn" do
    type_in("al", answered: false)
    type_in("ba", clear: false)
    wait_for_state("open")
    assert_equal "#{find_all("[role=option]").size} suggestions", status_text
  end

  test "Back after choosing a suggestion shows the field closed, with no list" do
    type_in("alba").send_keys(:down, :enter)
    assert_current_path(@albatross_path)
    page.go_back
    assert_current_path(@page_path)
    assert_equal "false", find("input[type=search]")["aria-expanded"]
    assert_no_selector "[role=option]"
  end

  test "at a phone's width the list is the field's width and the button stands under it" do
    at_window(390, height: 844) do
      open_page
      type_in("alba")
      list = box(".search-suggest__list")
      field = box(".search__input")
      button = box(".search__button")
      assert_in_delta field["width"], list["width"], 1, "the list is as wide as the field"
      assert_operator button["top"], :>=, list["bottom"], "the button is under the list"
    end
  end

  test "no suggestions in the preview" do
    sign_in_via_form(users(:one))
    visit_screen(PublicSite::Urls.new(preview: true).path_for(@page, "en"))
    assert_nil find("form[role=search]")["data-search-suggest-url-value"].presence
    assert_nil find("input[type=search]")["role"]
  end

  test "with the script blocked, the form sends as 0.7.0's" do
    with_script_blocked("search_suggest_controller") do
      open_page(connected: false)
      expect_js_error(/Failed to register controller: search-suggest/)
      type_in("alba", answered: false).send_keys(:enter)
      assert_current_path(/\?q=alba/)
      assert_nil find("input[type=search]")["role"]
    end
  end

  private

  def open_page(connected: true)
    visit @page_path
    await_js("(() => { const form = document.querySelector('#{FORM}'); return Boolean(window.Stimulus && form && window.Stimulus.getControllerForElementAndIdentifier(form, 'search-suggest')) })()") if connected
  end

  # Types `text` into the field (after emptying it, unless `clear: false`)
  # and returns the field. WAITS, when the field then holds two characters
  # or more, for the script to have drawn its answer to them: the listbox
  # stops being `aria-busy` and the state is one of the drawn ones. A test
  # that holds the answer (`delay_answers_for`) or wants no answer passes
  # `answered: false`.
  def type_in(text, clear: true, answered: true)
    field = find("input[type=search]")
    page.execute_script("arguments[0].value = ''; arguments[0].dispatchEvent(new Event('input', { bubbles: true }))", field) if clear
    field.send_keys(text)
    if answered && field.value.length >= 2
      await_js("(() => { const form = document.querySelector('#{FORM}'); const list = form.querySelector('[data-search-suggest-target=listbox]');" \
               " return list.getAttribute('aria-busy') !== 'true' && ['open', 'empty', 'limited', 'unavailable'].includes(form.dataset.searchSuggestState) })()",
               message: "no answer was drawn for #{field.value.inspect}")
    end
    field
  end

  # Waits for the form's `data-search-suggest-state` to be `name`.
  def wait_for_state(name) = assert_selector("#{FORM}[data-search-suggest-state='#{name}']")

  def state = find(FORM)["data-search-suggest-state"]

  def status_text = find("[data-search-suggest-target=status]", visible: :all).text(:all)

  def box(selector) = page.evaluate_script("(() => { const r = document.querySelector(#{selector.to_json}).getBoundingClientRect(); return { top: r.top, bottom: r.bottom, width: r.width } })()")

  # Whether the element carries the attribute at all (a node's `[]` answers
  # a property, which is "" for an absent `autocomplete`).
  def attribute?(node, name) = page.evaluate_script("arguments[0].hasAttribute(arguments[1])", node, name)

  def network = page.driver.browser.network

  # How many requests to a URL matching `pattern` the browser sent while the
  # block ran.
  def count_requests_to(pattern)
    network.clear(:traffic)
    yield
    network.traffic.count { |exchange| exchange.request&.url.to_s.match?(pattern) }
  end

  # The suggestion requests the block sends, each paused: one whose prefix
  # is `prefix` is continued `by` seconds later, any other at once. WAITS,
  # after the block, until that held request's exchange is finished in the
  # browser's traffic (its answer loaded, or the abort the script made of it
  # recorded), and then `await_frames` for the script's work on it, so a
  # test asserts on what the page made of the stale answer, not before it
  # arrived.
  def delay_answers_for(prefix, by:)
    held = Queue.new
    intercept_suggestions do |request|
      if suggest_of(request) == prefix
        Thread.new do
          sleep by # sleep: the answer for the stale prefix is held this long, inside the browser's request
          request.continue
          held << request.network_id
        end
      else
        request.continue
      end
    end
    yield
    id = held.pop(timeout: by + 5) or flunk("the request for #{prefix.inspect} was never held")
    assert_eventually(message: "the held request for #{prefix.inspect} never finished") { network.traffic.find { |exchange| exchange.id == id }&.finished? }
    await_frames
  ensure
    stop_intercepting
  end

  def suggest_of(request)
    JSON.parse(request.post_data.to_s)["suggest"]
  rescue JSON::ParserError
    nil
  end

  # Every suggestion request the block sends is answered with `body` (JSON)
  # and `status`, as the endpoint would answer it.
  def answer_suggestions_with(body, status:)
    intercept_suggestions do |request|
      request.respond(responseCode: status, body: body.to_json, responseHeaders: { "Content-Type" => "application/json" })
    end
    yield
  ensure
    stop_intercepting
  end

  def intercept_suggestions(&handle)
    network.intercept(pattern: "*/search/suggestions")
    @interception = page.driver.browser.page.on(:request) { |request, _index, _total| request.match?(SUGGESTIONS) ? handle.call(request) : request.continue }
  end

  def stop_intercepting
    page.driver.browser.page.off(:request, @interception) if @interception
    page.driver.browser.page.command("Fetch.disable")
    @interception = nil
  end

  # Within the block, a request for the module whose URL holds `name` is
  # aborted, as a browser that cannot fetch it would; the cache is off, so
  # the copy `setup`'s visit fetched is not used instead. Both are put back
  # after, also when the block fails: the browser is shared.
  def with_script_blocked(name)
    network.cache(disable: true)
    network.blocklist = [ %r{/controllers/#{Regexp.escape(name)}[-.]} ]
    yield
  ensure
    network.blocklist = []
    network.cache(disable: false)
  end
end
