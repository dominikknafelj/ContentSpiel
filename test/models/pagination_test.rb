require "test_helper"

class PaginationTest < ActiveSupport::TestCase
  test "the range and offset of a middle page" do
    pagination = Pagination.new(page: 2, per_page: 50, total: 312)
    assert_equal 50, pagination.offset
    assert_equal [ 51, 100 ], [ pagination.first_item, pagination.last_item ]
    assert_equal 7, pagination.total_pages
  end

  test "the last page ends at the total" do
    assert_equal 312, Pagination.new(page: 7, per_page: 50, total: 312).last_item
  end

  test "junk, zero and negative pages mean the first page" do
    [ nil, "", "abc", "0", "-3", "1.5e9x" ].each do |junk|
      assert_equal 1, Pagination.new(page: junk, per_page: 50, total: 312).page, junk.inspect
    end
  end

  test "a page past the end is out of range, not clamped and not an error" do
    pagination = Pagination.new(page: "9999", per_page: 50, total: 312)
    assert pagination.out_of_range?
    assert_equal 9999, pagination.page
  end

  test "an absurdly large page number doesn't overflow the offset" do
    pagination = Pagination.new(page: "9" * 40, per_page: 50, total: 312)
    assert_equal Pagination::MAX_PAGE, pagination.page
  end

  test "the page series keeps the ends and the neighbours, with gaps" do
    assert_equal [ 1, 2, 3, :gap, 7 ], Pagination.new(page: 1, per_page: 50, total: 312).series
    assert_equal [ 1, :gap, 3, 4, 5, :gap, 7 ], Pagination.new(page: 4, per_page: 50, total: 312).series
    assert_equal [ 1, 2, 3 ], Pagination.new(page: 2, per_page: 50, total: 120).series
  end

  test "one page or none is a single page" do
    assert Pagination.new(page: 1, per_page: 50, total: 50).single_page?
    assert Pagination.new(page: 1, per_page: 50, total: 0).single_page?
  end
end
