# Page-number pagination for CS Studio lists (design pass spec §4, handoff
# §9 A6): "51-100 OF 312" plus page links, the page in the URL. A value
# object so the arithmetic -- and what junk in `?page=` means -- lives in
# one place instead of once per controller: anything that isn't a positive
# integer is page 1; a page past the end is reported (`out_of_range?`), not
# silently clamped, so the list can say so and link back.
class Pagination
  MAX_PAGE = 1_000_000

  attr_reader :page, :per_page, :total

  def initialize(page:, per_page:, total:)
    @per_page = per_page
    @total = total
    @page = page.to_s.match?(/\A\d+\z/) ? page.to_s.to_i.clamp(1, MAX_PAGE) : 1
  end

  def offset = (page - 1) * per_page
  def total_pages = (total.to_f / per_page).ceil
  def first_item = total.zero? ? 0 : offset + 1
  def last_item = [ offset + per_page, total ].min
  def single_page? = total_pages <= 1
  def out_of_range? = total.positive? && page > total_pages

  # First, last, the current page and one neighbour each side; `:gap` where
  # pages are skipped. At either end the window widens to three.
  def series
    window = ((page - 1)..(page + 1)).to_a
    window = [ 1, 2, 3 ] if page <= 1
    window = ((total_pages - 2)..total_pages).to_a if page >= total_pages
    pages = ([ 1, total_pages ] + window).select { |n| n.between?(1, total_pages) }.uniq.sort
    pages.each_with_object([]) do |n, out|
      out << :gap if out.last.is_a?(Integer) && n > out.last + 1
      out << n
    end
  end
end
