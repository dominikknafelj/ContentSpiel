require "test_helper"

# `Media::Search` (round 3, Task 8, decision D13): the library's search and
# its four segments, and the counts the segments carry. The old
# `Media::Search.call(scope, query)` (MCP, the ⌘K palette) is pinned by
# `test/integration/mcp_media_test.rb` and `test/queries/jump/search_test.rb`.
class Media::SearchTest < ActiveSupport::TestCase
  include ContentHelper

  setup do
    with_locales(%w[en de], default: "en")
    @viewer = users(:one)
    # Alt in English only: a German alt is missing, so it is "untranslated".
    @translated_gap = create_media_asset.tap { |asset| save(asset, "en" => { alt: "Sand dunes" }) }
    # Alt in German only: the default-language alt is blank.
    @german_only = create_media_asset.tap { |asset| save(asset, "de" => { alt: "Nur Deutsch" }) }
    # Alt in both: complete, and not missing alt.
    @complete = create_media_asset.tap { |asset| save(asset, "en" => { alt: "Beach" }, "de" => { alt: "Strand" }) }
    # No alt at all: missing alt, but with nothing to translate it isn't "untranslated".
    @bare = create_media_asset.tap { |asset| asset.update!(created_by: @viewer) }
    @trashed = create_media_asset.tap { |asset| asset.update!(trashed_at: Time.current) }

    page = create_page(title: "Hero page")
    assert Pages::Save.call(page, attributes: { hero_media_asset_id: @complete.id }).ok?
  end

  test "any_images? is the kept count without search text, and one query with it: a search that finds nothing still knows" do
    plain = Media::Search.new(actor: @viewer)
    assert plain.any_images?(counts: plain.counts)

    nothing = Media::Search.new(q: "no such image anywhere", actor: @viewer)
    assert_equal 0, nothing.counts[:all]
    assert nothing.any_images?(counts: nothing.counts)

    Media::Asset.update_all(trashed_at: Time.current) # version: none (a test's own setup: the whole library in the trash)
    [ Media::Search.new(actor: @viewer), Media::Search.new(q: "Beach", actor: @viewer) ].each do |search|
      assert_not search.any_images?(counts: search.counts)
    end
  end

  test "each segment lists what its name says" do
    assert_equal [ @bare, @complete, @german_only, @translated_gap ].map(&:id).sort, ids(filter: "all")
    assert_equal [ @bare, @german_only, @translated_gap ].map(&:id).sort, ids(filter: "unused")
    assert_equal [ @bare, @german_only ].map(&:id).sort, ids(filter: "missing_alt")
    assert_equal [ @translated_gap.id ], ids(filter: "untranslated")
    assert_equal [ @bare.id ], ids(filter: "mine")
  end

  test "an asset with alt only in German is missing alt while English is the default" do
    assert_includes ids(filter: "missing_alt"), @german_only.id
    assert_not_includes ids(filter: "missing_alt"), @translated_gap.id
  end

  test "an asset with no state rows is not untranslated" do
    Translations::State.where(record_type: "Media::Asset").delete_all

    assert_empty ids(filter: "untranslated")
  end

  test "the counts are one grouped query, kept only, and ignore the segment" do
    expected = { all: 4, unused: 3, missing_alt: 2, untranslated: 1, mine: 1 }

    assert_equal expected, Media::Search.new(filter: "unused", actor: @viewer).counts
    assert_equal expected, Media::Search.new(filter: "all", actor: @viewer).counts

    queries = []
    counter = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { Media::Search.new(actor: @viewer).counts }
    assert_equal 1, queries.size, queries.join("\n")
  end

  test "the counts respect the search" do
    asset = create_media_asset(filename: "wide.png")
    asset.update!(title: "Needle")

    counts = Media::Search.new(q: "needle", actor: @viewer).counts

    assert_equal({ all: 1, unused: 1, missing_alt: 1, untranslated: 0, mine: 0 }, counts)
  end

  test "Mine is the viewer's own uploads, and a token is judged as its user" do
    group = AccessControl::Group.create!(name: "Tokens #{SecureRandom.hex(3)}")
    token = ApiToken.new(user: @viewer, group: group, name: "Mine test")

    assert_equal [ @bare.id ], Media::Search.new(filter: "mine", actor: token).results.map(&:id)
    assert_equal 0, Media::Search.new(actor: nil).counts[:mine]
  end

  test "untranslated is not a segment on a one-language site" do
    with_locales(%w[en], default: "en")

    search = Media::Search.new(filter: "untranslated", actor: @viewer)

    assert_equal "all", search.filter
    assert_equal 4, search.results.count
    assert_equal 0, search.counts[:untranslated]
  end

  test "an unknown or forged filter is all, and a non-string query is no search" do
    assert_equal "all", Media::Search.new(filter: "bogus").filter
    assert_equal "all", Media::Search.new(filter: [ "mine" ]).filter
    assert_equal 4, Media::Search.new(q: [ "x" ]).results.count
  end

  test "the query still matches title, alt in any locale and filename" do
    @bare.update!(title: "Sunset over water")

    assert_equal [ @bare.id ], Media::Search.new(q: "sunset").results.map(&:id)
    assert_equal [ @german_only.id ], Media::Search.new(q: "nur deutsch").results.map(&:id)
    assert_equal 4, Media::Search.new(q: "tiny").results.count
    assert_equal [ @german_only.id ], Media::Search.new(q: "deutsch", filter: "missing_alt").results.map(&:id)
  end

  # The segments' conditions are nodes shared by the list and its number, so
  # the two can't disagree: each count is the size of its list.
  test "every count is the size of the list its segment gives, with and without a search" do
    [ nil, "dunes", "50%_o\\ff 'x'" ].each do |q|
      counts = Media::Search.new(q: q, actor: @viewer).counts

      Media::Search::FILTERS.each do |filter|
        assert_equal Media::Search.new(q: q, filter: filter, actor: @viewer).results.count, counts.fetch(filter.to_sym), "#{filter} for #{q.inspect}"
      end
    end
  end

  test "an alt that is only whitespace, or absent in the default language, is missing; a typed quote or wildcard is only text" do
    blank = create_media_asset.tap { |asset| asset.update_columns(alt: { "en" => " \n\t" }) }
    quoted = create_media_asset.tap { |asset| asset.update!(title: "Baker's 100%") }

    assert_includes ids(filter: "missing_alt"), blank.id
    assert_not_includes ids(filter: "missing_alt"), @complete.id
    assert_equal [ quoted.id ], Media::Search.new(q: "r's 100%").results.map(&:id)
    assert_empty Media::Search.new(q: "r's 1%0").results
  end

  private

  def save(asset, translations)
    assert Media::Save.call(asset, translations: translations).ok?
  end

  def ids(**options) = Media::Search.new(actor: @viewer, **options).results.map(&:id).sort
end
