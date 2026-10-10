require "test_helper"

class Admin::Ui::PaginationComponentTest < ViewComponent::TestCase
  setup { @url = ->(page) { "/list?page=#{page}" } }

  test "the range on the left and page links on the right" do
    render_inline(Admin::Ui::PaginationComponent.new(pagination: Pagination.new(page: 2, per_page: 50, total: 312), url: @url))
    assert_selector "nav[aria-label='Pagination']"
    assert_text "51–100 OF 312"
    assert_selector "a[rel=prev][href='/list?page=1']", text: "Previous"
    assert_selector "a[rel=next][href='/list?page=3']", text: "Next"
    assert_selector "[aria-current=page]", text: "2"
    assert_selector "a[href='/list?page=7']", text: "7"
  end

  test "hidden on a single page" do
    render_inline(Admin::Ui::PaginationComponent.new(pagination: Pagination.new(page: 1, per_page: 50, total: 12), url: @url))
    assert_no_selector "nav"
  end

  test "no Previous on the first page, no Next on the last" do
    render_inline(Admin::Ui::PaginationComponent.new(pagination: Pagination.new(page: 1, per_page: 50, total: 120), url: @url))
    assert_no_selector "a[rel=prev]"
    assert_selector "a[rel=next]"
    render_inline(Admin::Ui::PaginationComponent.new(pagination: Pagination.new(page: 3, per_page: 50, total: 120), url: @url))
    assert_no_selector "a[rel=next]"
    assert_selector "a[rel=prev]"
  end
end
