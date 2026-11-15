require "test_helper"

# The suggestions while typing, through the request (search 2 spec §4.1,
# §4.2): `POST /search/suggestions` with a JSON body, no CSRF token,
# refused by another site's browser, capped before anything parses the
# body (`ContentSpiel::SuggestGate`), limited on counters of its own, and
# answered with nothing a visitor of the public site cannot see.
class SiteSearch::SuggestionsControllerTest < ActionDispatch::IntegrationTest
  include LogCapture

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    root_page
    @exporter = Rails.application.config.x.otel_test_exporter
    @exporter.reset
  end

  # A visitor's script's request: `fields` are the body, `{ suggest: "alba",
  # language: "en" }` when none are given; `raw` is the body as sent; a
  # header given as nil is not sent.
  def suggest(body = nil, headers: {}, raw: nil, **fields)
    body ||= fields.presence || { suggest: "alba", language: "en" }
    post "/search/suggestions", params: raw || body.to_json,
      headers: { "Content-Type" => "application/json", "Sec-Fetch-Site" => "same-origin" }.merge(headers).compact
  end

  # A POST whose body has no length, as a chunked one arrives.
  def chunked_post(path, body)
    post path, env: { "rack.input" => StringIO.new(body), "CONTENT_LENGTH" => nil, "HTTP_TRANSFER_ENCODING" => "chunked",
      "CONTENT_TYPE" => "application/json", "HTTP_SEC_FETCH_SITE" => "same-origin" }
  end

  def counter_key(name)
    by = name == "suggest_site" ? "site" : VisitorAddress.key("127.0.0.1", purpose: SiteSearch::QueryLimit::KEY_PURPOSE)
    "rate-limit:#{SiteSearch::SuggestLimit::SCOPE}:#{name}:#{by}"
  end

  def suggest_counter(name) = SiteSearch::SuggestLimit.store.read(counter_key(name), raw: true).to_i

  # The counter `name` raised by `count` before the block.
  def with_suggest_counter(name, count)
    SiteSearch::SuggestLimit.store.increment(counter_key(name), count, expires_in: SiteSearch::SuggestLimit::WITHIN)
    yield
  end

  # No backend's `suggest` is called inside the block.
  def assert_no_backend_asked(&block)
    SiteSearch::Fake.new.installed do |fake|
      block.call
      assert_empty fake.suggested, "a backend was asked"
    end
  end

  def with_forgery_protection
    before = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = before
  end

  # A page or a post that is published. The services publish on create.
  def publish(record)
    assert record.reload.published_at, "#{record.class.name} #{record.id} is published"
    record
  end

  def blog
    @blog ||= create_page(title: "Blog").tap do |page|
      assert ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).ok?
      publish_changes(page)
    end
  end

  def request_span = @exporter.finished_spans.reverse.find { |span| span.kind == :server }

  def urls = response.parsed_body["suggestions"].map { _1["url"] }

  def tag_urls = response.parsed_body["suggestions"].select { _1["kind"] == "tag" }.map { _1["url"] }

  REFUSED = { "state" => "refused", "status" => "", "suggestions" => [] }.freeze

  test "a POST with Sec-Fetch-Site cross-site, or an Origin of another host, is refused with 403 and asks nothing" do
    assert_no_backend_asked do
      suggest(headers: { "Sec-Fetch-Site" => "cross-site" }); assert_response :forbidden
      assert_equal REFUSED, response.parsed_body
      suggest(headers: { "Sec-Fetch-Site" => "same-site" }); assert_response :forbidden
      suggest(headers: { "Sec-Fetch-Site" => nil, "Origin" => "https://evil.example" }); assert_response :forbidden
      suggest(headers: { "Sec-Fetch-Site" => nil, "Origin" => "null" }); assert_response :forbidden
    end
    assert_equal REFUSED, response.parsed_body
  end

  test "a POST of text/plain or form data is refused, whatever its Origin" do
    [ "text/plain", "application/x-www-form-urlencoded", nil ].each do |type|
      suggest(headers: { "Content-Type" => type, "Origin" => "http://www.example.com" }); assert_response :forbidden, type.inspect
    end
  end

  test "a POST of the site's own origin, or with neither header, is answered and counted" do
    suggest(headers: { "Sec-Fetch-Site" => nil, "Origin" => "http://www.example.com" }); assert_response :ok
    suggest(headers: { "Sec-Fetch-Site" => nil }); assert_response :ok
    assert_equal "ok", response.parsed_body["state"]
    assert_equal 2, suggest_counter("suggest_visitor")
    assert_equal 2, suggest_counter("suggest_site")
  end

  test "a body over 1 KB is a 413 before it is parsed, with or without a length" do
    suggest(raw: { suggest: "a" * 2_000 }.to_json); assert_response :content_too_large
    assert_equal REFUSED, response.parsed_body
    assert_equal "private, no-store", response.headers["Cache-Control"]
    chunked_post("/search/suggestions", "{\"suggest\":\"#{"a" * 2_000}\"}"); assert_response :content_too_large

    chunked_post("/search/suggestions", { suggest: "alba", language: "en" }.to_json)
    assert_response :ok, "a short body with no length is read"
  end

  test "malformed JSON, or a suggest that is no String, is a 400" do
    suggest(raw: "{not json"); assert_response :bad_request
    assert_equal REFUSED, response.parsed_body
    suggest(raw: ""); assert_response :bad_request
    suggest(raw: "[\"alba\"]"); assert_response :bad_request
    suggest(suggest: [ "a" ]); assert_response :bad_request
    suggest(suggest: { "a" => 1 }); assert_response :bad_request
    suggest(language: "en"); assert_response :bad_request
  end

  test "a malformed body is a 400 and its text is in no log line" do
    log = capture_log(LogCapture::REQUEST_LOGGERS) do
      Rails.logger.level = :debug
      suggest(raw: "{\"suggest\": \"secretprefix")
      assert_response :bad_request
      suggest(raw: "{\"suggest\": \"secretprefix#{"x" * 2_000}\"}")
      assert_response :content_too_large
    end
    assert_match %r{Started POST "/search/suggestions"}, log
    refute_includes log, "secretprefix"
  end

  test "an unknown language is the default's" do
    page = publish(create_page(title: "Albatross"))
    suggest(suggest: "alba", language: "xx")
    assert_equal [ PublicSite::Urls.new.path_for(page, "en") ], urls

    suggest(suggest: "alba", language: [ "en" ])
    assert_response :ok, "a language that is no String is the default's too"
    assert_equal [ PublicSite::Urls.new.path_for(page, "en") ], urls
  end

  test "a language that is switched on is the one asked, a code that is not is the default" do
    with_locales(%w[en de], default: "en") do
      page = create_page(title: "Albatross", translations: { "de" => { title: "Albatros" } })
      suggest(suggest: "alba", language: "de")
      assert_equal [ PublicSite::Urls.new.path_for(page, "de") ], urls
      assert_equal "1 suggestion", response.parsed_body["status"]

      suggest(suggest: "alba", language: "es")
      assert_equal [ PublicSite::Urls.new.path_for(page, "en") ], urls, "es is in the supported list but not switched on"
    end
  end

  test "no CSRF token is asked, and none is minted" do
    with_forgery_protection do
      suggest; assert_response :ok
      assert_nil response.headers["Set-Cookie"]
    end
  end

  test "the answer is the spec's JSON: its state, its sentence and each suggestion's kind, label, place, address and marks" do
    page = create_page(title: "Albatross colonies", parent: create_page(title: "Seabirds"))
    suggest(suggest: "alba")
    assert_response :ok
    assert_equal "application/json", response.media_type
    assert_equal({ "state" => "ok", "status" => "1 suggestion",
      "suggestions" => [ { "kind" => "page", "kind_label" => "Page", "label" => "Albatross colonies", "where" => "Home › Seabirds",
        "url" => PublicSite::Urls.new.path_for(page, "en"), "marks" => [ [ 0, 4 ] ] } ] }, response.parsed_body)

    suggest(suggest: "zzzz")
    assert_equal({ "state" => "ok", "status" => "No suggestions. Press Enter to search.", "suggestions" => [] }, response.parsed_body)
  end

  test "a title like <img onerror> is text in the JSON" do
    publish(create_page(title: %(<img src=x onerror=alert(1)> Albatross)))
    suggest(suggest: "albat")
    refute_includes response.body, "<img"
    assert_includes response.parsed_body["suggestions"].first["label"], "<img src=x onerror=alert(1)>"
  end

  test "a tag like markup is text in the JSON" do
    place_search_block(root_page)
    blog
    publish(create_post(title: "P", tags: [ %(<script>x</script>alba) ]))
    suggest(suggest: "<scr")
    refute_includes response.body, "<script>"
    tag = response.parsed_body["suggestions"].find { _1["kind"] == "tag" }
    assert_equal "<script>x</script>alba", tag["label"]
    assert_equal "Tag", tag["kind_label"]
  end

  test "a tag with no listing page is a search for it on the site's search page, and a trashed listing page is no listing" do
    place_search_block(root_page)
    blog
    publish(create_post(title: "P", tags: %w[deployment]))
    search_path = "#{PublicSite::Urls.new.path_for(root_page, "en")}?#{{ q: "deployment" }.to_query}"

    suggest(suggest: "depl")
    assert_equal [ search_path ], tag_urls

    tag = Tag.find_by!(name: "deployment")
    listing = create_page(title: "Tagged posts")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: listing), attributes: { block_type: "post_list", settings: { "tag" => tag.name } }).ok?
    publish_changes(listing)
    suggest(suggest: "depl")
    assert_equal [ PublicSite::Urls.new.path_for(listing, "en") ], tag_urls, "a tag's listing page"

    assert Trash::Move.call(listing.reload).ok?
    suggest(suggest: "depl")
    assert_equal [ search_path ], tag_urls, "a trashed listing page is no tag's page"
  end

  test "the 121st suggestion of a minute is refused with 429 and limited, and no backend is asked" do
    120.times { suggest; assert_response :ok }
    assert_no_backend_asked { suggest }
    assert_response :too_many_requests
    assert_equal({ "state" => "limited", "status" => "Too many suggestions asked. Press Enter to search.", "suggestions" => [] }, response.parsed_body)
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal "limited", request_span.attributes["search.outcome"]

    travel SiteSearch::SuggestLimit::WITHIN + 1.second do
      suggest; assert_response :ok, "a minute later the visitor is answered again"
    end
  end

  test "with every slot in flight a suggestion answers limited at once, and no backend is asked" do
    slots = SiteSearch::SuggestLimit::SLOTS
    assert slots.try_acquire(SiteSearch::SuggestLimit::IN_FLIGHT), "the test holds every slot"
    begin
      assert_no_backend_asked { suggest }
      assert_response :too_many_requests
      assert_equal "limited", response.parsed_body["state"]
      assert_equal "limited", request_span.attributes["search.outcome"]
      assert_nil @exporter.finished_spans.find { |span| span.name == "search.suggest" }
    ensure
      slots.release(SiteSearch::SuggestLimit::IN_FLIGHT)
    end
    suggest; assert_response :ok, "a slot freed is taken again"
    assert_equal SiteSearch::SuggestLimit::IN_FLIGHT, slots.available_permits
  end

  test "a suggestion that raises gives its slot back" do
    with_singleton_override(SiteSearch, :suggest, ->(**) { raise ActiveRecord::ConnectionNotEstablished, "down" }) do
      assert_raises(ActiveRecord::ConnectionNotEstablished) { suggest } # raised through: the test environment renders only rescuable errors
    end
    assert_equal SiteSearch::SuggestLimit::IN_FLIGHT, SiteSearch::SuggestLimit::SLOTS.available_permits
  end

  test "the site limit refuses the 3,001st" do
    with_suggest_counter("suggest_site", SiteSearch::SuggestLimit::SITE_LIMIT) { suggest; assert_response :too_many_requests }
    assert_equal "limited", response.parsed_body["state"]
  end

  test "suggestions spend nothing of the search limit, and the reverse" do
    20.times { get "/?q=albatross" }
    suggest; assert_response :ok
    110.times { suggest }
    get "/?q=gull"; assert_response :too_many_requests # the search's own 21st, not the suggestions'
  end

  test "a refused, oversized or malformed request counts nothing" do
    suggest(headers: { "Sec-Fetch-Site" => "cross-site" }); suggest(raw: "x" * 2_000); suggest(raw: "{")
    suggest(headers: { "Content-Type" => "text/plain" }); suggest(suggest: 7)
    assert_equal 0, suggest_counter("suggest_visitor")
    assert_equal 0, suggest_counter("suggest_site")
  end

  test "a refusal is on the request's span as search.outcome, and search.suggest is never started for it" do
    suggest(headers: { "Sec-Fetch-Site" => "cross-site" })
    assert_equal "refused", request_span.attributes["search.outcome"]
    suggest(raw: "{")
    assert_equal "refused", request_span.attributes["search.outcome"]
    suggest(raw: "x" * 2_000)
    assert_equal "refused", request_span.attributes["search.outcome"]
    assert_not @exporter.finished_spans.any? { |span| span.name == "search.suggest" }

    suggest
    assert_nil request_span.attributes["search.outcome"], "an answer's outcome is search.suggest's"
    assert_equal "ok", @exporter.finished_spans.find { |span| span.name == "search.suggest" }.attributes["search.outcome"]
  end

  test "a prefix under 2 or over 100 characters asks nothing and answers ok" do
    assert_no_backend_asked { suggest(suggest: "a"); suggest(suggest: "a" * 101) }
    assert_equal "ok", response.parsed_body["state"]
  end

  test "a backend that sleeps past 0.2 s answers unavailable within 0.3 s and a 200" do
    SiteSearch::Fake.new(sleep_for: 1).installed do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      suggest
      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 0.6, "0.3 s, with a margin for a busy machine"
      assert_response :ok
      assert_equal({ "state" => "unavailable", "status" => "Suggestions aren't available right now. Press Enter to search.", "suggestions" => [] }, response.parsed_body)
    end
  end

  test "the gate takes the path as the router does: a trailing or doubled slash is gated too" do
    [ "/search/suggestions/", "//search//suggestions" ].each do |path|
      post path, params: "{\"suggest\":\"#{"a" * 2_000}\"}", headers: { "Content-Type" => "application/json", "Sec-Fetch-Site" => "same-origin" }
      assert_response :content_too_large, path
      post path, params: "{nope", headers: { "Content-Type" => "application/json", "Sec-Fetch-Site" => "same-origin" }
      assert_response :bad_request, path
    end
  end

  test "with ADMIN_HOST set it answers on the public host alone" do
    with_site_address("https://docs.example.org") do
      with_admin_address("https://studio.example.internal") do
        host! "studio.example.internal"
        https!
        suggest
        assert_response :not_found
        suggest(raw: "{\"suggest\":\"#{"a" * 2_000}\"}")
        assert_response :not_found, "the gate leaves the admin host to the router"

        host! "docs.example.org"
        suggest(headers: { "Sec-Fetch-Site" => nil, "Origin" => "https://docs.example.org" })
        assert_response :ok
      end
    end
  end
end
