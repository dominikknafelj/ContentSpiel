require "test_helper"

# What the Search block draws (spec §7.2): the state of a request's search,
# decided before any backend is asked where it can be (no query, too long,
# limited), and from the backend's answer otherwise, with its hits
# re-checked and its page.
class SiteSearch::AnswerTest < ActiveSupport::TestCase
  # A backend that fails the test when it is asked anything.
  class Untouchable < SiteSearch::Fake
    def search(*) = raise(Minitest::Assertion, "the backend was asked")
  end

  def answer(raw_query, raw_page: nil, limited: false, live_note: false)
    SiteSearch::Answer.for(raw_query: raw_query, raw_page: raw_page, locale: :en, limited: limited, live_note: live_note)
  end

  def untouched(&) = Untouchable.new.installed(&)

  test "no q or a blank q is empty and asks no backend" do
    untouched do
      [ nil, "", "   \n ", [ "a" ], "\u0000" ].each do |raw|
        answer = answer(raw)
        assert_equal :empty, answer.state, raw.inspect
        assert_nil answer.query
        assert_empty answer.results
        assert_equal 0, answer.total
        assert_equal 1, answer.pagination.page
      end
    end
  end

  test "a query over 200 characters is too_long, keeps the text and asks no backend" do
    typed = "  #{"a" * 201} "
    untouched do
      answer = answer(typed)
      assert_equal :too_long, answer.state
      assert_equal typed, answer.query
      assert_empty answer.results
    end
    assert_equal :none, answer("a" * 200).state, "200 characters are searched"
  end

  test "limited asks no backend" do
    untouched do
      answer = answer("albatross", limited: true)
      assert_equal :limited, answer.state
      assert_equal "albatross", answer.query
      assert_empty answer.results
    end
  end

  test "no hits is none, hits are results with the total" do
    page = create_page(title: "Albatross")
    create_page(title: "Albatross again")

    none = answer("  pelican ")
    assert_equal :none, none.state
    assert_equal "pelican", none.query
    assert_empty none.results

    found = answer("albatross")
    assert_equal :results, found.state
    assert_equal 2, found.total
    assert_equal 2, found.pagination.total
    assert_equal 10, found.pagination.per_page
    assert_includes found.results.map { |item| item.record.id }, page.id
    assert found.results.all? { |item| item.is_a?(SiteSearch::Shown::Item) }
    assert_not found.past_end?
  end

  test "a page number that is junk reads page 1 and a huge one is past the end" do
    create_page(title: "Albatross")

    [ "abc", "0", "-3", nil, [ "2" ] ].each do |raw|
      answer = answer("albatross", raw_page: raw)
      assert_equal 1, answer.pagination.page, raw.inspect
      assert_equal :results, answer.state
      assert_equal 1, answer.results.size
    end

    huge = answer("albatross", raw_page: "99999999999999")
    assert_equal :results, huge.state
    assert huge.past_end?
    assert_empty huge.results
    assert_equal 1, huge.total
  end

  test "unavailable from the backend is the unavailable state" do
    SiteSearch::Fake.new(raise_with: RuntimeError.new("down")).installed do
      answer = nil
      assert_error_reported(SiteSearch::Unavailable) { answer = answer("albatross") }
      assert_equal :unavailable, answer.state
      assert_equal "albatross", answer.query
      assert_empty answer.results
    end
  end

  test "the live note is the caller's" do
    assert answer("albatross", live_note: true).live_note?
    assert_not answer("albatross").live_note?
    assert answer(nil, live_note: true).live_note?
  end
end
