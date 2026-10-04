module Admin
  # "51–100 OF 312" on the left, Previous / page numbers / Next on the right
  # (design pass spec §4, handoff §9 A6), at the foot of a list's card. The
  # arithmetic is `Pagination`'s; `url:` is the caller's `->(page) { path }`,
  # which keeps the list's own filters (callers merge `page` into
  # `list_params(...)`, `Admin::ListLinksHelper` -- the filter keys that list
  # names, never `request.query_parameters` wholesale). Nothing renders on a
  # single page.
  class PaginationComponent < AdminComponent
    LINK_CLASS = "rounded-cs px-2 py-0.5 text-sm text-dim hover:bg-sunken".freeze
    CURRENT_CLASS = "rounded-cs bg-sunken px-2 py-0.5 text-sm text-ink".freeze

    def initialize(pagination:, url:)
      @pagination = pagination
      @url = url
    end

    def render? = !pagination.single_page? && !pagination.out_of_range?

    private

    attr_reader :pagination, :url

    def previous? = pagination.page > 1
    def next? = pagination.page < pagination.total_pages
  end
end
