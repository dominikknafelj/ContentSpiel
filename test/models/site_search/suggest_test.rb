require "test_helper"

# `SiteSearch.suggest` (search 2 spec §4.3): up to five titles from the
# backend's optional `suggest`, re-checked as hits are, then up to three
# tags of live posts, each kind filling the other's gap up to eight, every
# label marked where a prefix word begins one of its words; one deadline of
# `SUGGEST_TIMEOUT`, the backend's share `SUGGEST_BACKEND_SHARE`, and a
# failure `:unavailable`, reported with its own minute.
class SiteSearch::SuggestTest < ActiveSupport::TestCase
  PREFIX = "zanzibarcanary".freeze

  setup do
    @exporter = Rails.application.config.x.otel_test_exporter
    @exporter.reset
    @blog = create_page(title: "Blog")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: @blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).ok?
    publish_changes(@blog)
  end

  def publish(record) = record

  def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def suggest(text, language: "en") = SiteSearch.suggest(text: text, language: language, now: Time.current)

  def suggest_one(prefix, title:)
    create_page(title: title)
    suggest(prefix).items.sole
  end

  def in_request(&block) = OpenTelemetry.tracer_provider.tracer("site-search-test").in_span("POST /search/suggestions", kind: :server, &block)

  def recorded_span(name, &block)
    @exporter.reset
    in_request(&block)
    @exporter.finished_spans.find { |each| each.name == name }.tap { |span| assert span, @exporter.finished_spans.map(&:name).inspect }
  end

  def statements_of
    statements = []
    ActiveSupport::Notifications.subscribed(->(*, payload) { statements << payload[:sql] unless %w[TRANSACTION SCHEMA].include?(payload[:name]) || payload[:cached] }, "sql.active_record") { yield }
    statements
  end

  def place_search_page
    page = create_page(title: "Search")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "search" }).ok?
    publish_changes(page)
  end

  test "up to five titles then up to three tags, each kind filling the other's gap" do
    place_search_page
    7.times { publish(create_page(title: "Albatross #{_1}")) }
    publish(create_post(title: "x", tags: %w[albatrosses albatross-watch]))
    kinds = SiteSearch.suggest(text: "alba", language: "en", now: Time.current).items.map(&:kind)
    assert_equal [ :page ] * 6 + [ :tag ] * 2, kinds # 2 tags leave 1 of 3 tag places to a sixth title
  end

  test "five titles and three tags when both kinds have more" do
    place_search_page
    7.times { create_page(title: "Albatross #{_1}") }
    create_post(title: "x", tags: %w[alba-one alba-two alba-three alba-four])
    assert_equal [ :page ] * 5 + [ :tag ] * 3, suggest("alba").items.map(&:kind)
  end

  test "tags fill the places titles leave" do
    place_search_page
    create_page(title: "Albatross")
    create_post(title: "x", tags: (1..9).map { "alba-#{_1}" })
    assert_equal [ :page ] + [ :tag ] * 7, suggest("alba").items.map(&:kind)
  end

  test "marks are where a prefix word begins a word of the label" do
    item = suggest_one("zero deploym", title: "Zero-downtime deployments")
    assert_equal [ [ 0, 4 ], [ 14, 7 ] ], item.marks
    assert_equal [ [ 0, 2 ], [ 14, 2 ] ], SiteSearch::SuggestAnswer.marks_of("Zero-downtime deployments", "ze de", limited: false)
    assert_equal [ [ 2, 4 ], [ 7, 4 ] ], SiteSearch::SuggestAnswer.marks_of("検索エンジンとエンジン", "エンジン", limited: true)
  end

  test "an item is a page's title, place and address, a post's date, or a tag's listing" do
    parent = create_page(title: "Guides")
    page = create_page(title: "Albatross care", parent: parent)
    post = create_post(title: "Albatross sighted", tags: %w[albatross])
    items = suggest("albatross").items.index_by(&:kind)

    assert_equal [ "Albatross care", "Home › Guides", PublicSite::Urls.new.path_for(page, "en") ], items[:page].to_h.values_at(:label, :where, :url)
    assert_equal post.reload.published_at.strftime(SiteSearch::SuggestAnswer::DATE_FORMAT), items[:post].where
    assert_equal Blocks::SearchComponent::Result::DATE_FORMAT, SiteSearch::SuggestAnswer::DATE_FORMAT, "a post's date as a result writes it"
    assert_equal Blocks::SearchComponent::Result::PLACE_SEPARATOR, SiteSearch::SuggestAnswer::PLACE_SEPARATOR
    assert_nil items[:tag], "a tag with no listing and no search page is left out"

    search = place_search_page
    tag = suggest("albatross").items.find { _1.kind == :tag }
    assert_equal [ "albatross", nil, "#{PublicSite::Urls.new.path_for(search, "en")}?q=albatross" ], tag.to_h.values_at(:label, :where, :url)

    listing = create_page(title: "Albatross listing")
    assert ContentBlocks::Save.call(ContentBlock.new(owner: listing), attributes: { block_type: "post_list", settings: { "tag" => "albatross" } }).ok?
    publish_changes(listing)
    assert_equal PublicSite::Urls.new.path_for(listing, "en"), suggest("albatross").items.find { _1.kind == :tag }.url
  end

  test "under two characters, over a hundred or nothing but spaces asks nothing" do
    SiteSearch::Fake.new.installed do |fake|
      [ "a", " a ", "a" * (SiteSearch::MAX_PREFIX + 1), "   ", nil ].each do |text|
        answer = suggest(text)
        assert_equal [ :ok, [] ], [ answer.state, answer.items ], text.inspect
      end
      assert_empty fake.suggested
    end
  end

  test "a backend without suggest offers tags only, and System status says so" do
    place_search_page
    page = create_page(title: "Albatross")
    create_post(title: "x", tags: %w[albatross])
    SiteSearch::Fake.new(suggests: false).installed do |fake|
      fake.index(SiteSearch::Documents.for_record(page, now: Time.current))
      items = SiteSearch.suggest(text: "alba", language: "en", now: Time.current).items
      assert_equal [ :tag ], items.map(&:kind)
      assert_includes Setup::SystemCheck.new.send(:search).note, "offers no title suggestions"
    end
    assert_nil Setup::SystemCheck.new.send(:search).note, "the built-in suggests titles"
  end

  test "a backend's suggestions are re-checked: a stale title is dropped and the label is the copy's" do
    page = create_page(title: "Albatross")
    draft = create_page(title: "Albatross draft", published: false)
    SiteSearch::Fake.new.installed do |fake|
      fake.index(SiteSearch::Documents.for_record(page, now: Time.current))
      stale = SiteSearch::Documents.for_record(page, now: Time.current).first
      fake.index([ stale.with(key: "Page:#{draft.id}:1:en", record_id: draft.id) ])
      assert Pages::Save.call(page.reload, translations: { "en" => { title: "Albatross renamed" } }).ok?
      assert_equal [ "Albatross" ], suggest("alba").items.map(&:label)
    end
  end

  test "a backend that sleeps past 0.2 s answers unavailable within 0.3 s" do
    SiteSearch::Fake.new(sleep_for: 1).installed do
      started = clock
      assert_equal :unavailable, SiteSearch.suggest(text: "alba", language: "en", now: Time.current).state
      assert_operator clock - started, :<, 0.35
    end
  end

  test "a backend that raises answers unavailable, reported by its own minute without the message" do
    SiteSearch::Fake.new(raise_with: RuntimeError.new("http://engine/suggest?q=#{PREFIX}")).installed do
      report = assert_error_reported(SiteSearch::Unavailable) do
        assert_equal [ :unavailable, [] ], suggest(PREFIX).to_h.values_at(:state, :items)
      end
      assert_not_includes report.error.message, PREFIX
      assert_no_error_reported { suggest(PREFIX) }
    end
  end

  test "an answer of the wrong shape is unavailable" do
    [ [ 1 ], SiteSearch::Suggestions.new(items: [ :nope ]), SiteSearch::Suggestions.new(items: "x"),
      SiteSearch::Suggestions.new(items: [ SiteSearch::Suggestion.new(record_type: "Page", record_id: "1", copy_id: 1, rank: 0) ]) ].each do |answer|
      fake = SiteSearch::Fake.new
      fake.define_singleton_method(:suggest) { |*, **| answer }
      fake.installed { assert_equal :unavailable, suggest("alba").state, answer.inspect }
    end
  end

  test "search.suggest records backend, outcome and count, never the prefix" do
    span = recorded_span("search.suggest") { SiteSearch.suggest(text: "albatross", language: "en", now: Time.current) }
    assert_equal %w[search.backend search.outcome search.suggestions].sort, span.attributes.keys.sort
    assert_equal [ "postgres", "ok", 0 ], span.attributes.values_at("search.backend", "search.outcome", "search.suggestions")

    SiteSearch::Fake.new(raise_with: RuntimeError.new(PREFIX)).installed do
      span = recorded_span("search.suggest") { suggest(PREFIX) }
      assert_equal "unavailable", span.attributes["search.outcome"]
      refute (span.attributes.values.map(&:to_s) + span.events.to_a.map(&:to_s)).any? { _1.include?(PREFIX) }
    end
  end

  test "the statements are the same for two suggestions as for eight, and the prefix is a bind" do
    place_search_page
    create_page(title: "Zanzibar one")
    create_post(title: "Zanzibar post", tags: %w[zanzibar-a])
    few = statements_of { assert_equal 3, suggest("zanzib").items.size }
    4.times { create_page(title: "Zanzibar #{_1}") }
    create_post(title: "Zanzibar later", tags: %w[zanzibar-b zanzibar-c])
    many = statements_of { assert_equal 8, suggest("zanzib").items.size }
    assert_equal few.size, many.size, (many - few).join("\n")
    refute many.any? { _1.downcase.include?("zanzib") }
  end
end
