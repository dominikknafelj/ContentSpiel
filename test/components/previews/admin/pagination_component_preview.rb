module Admin
  # `Admin::PaginationComponent` (design pass spec §4): a middle page of many,
  # with gaps on both sides.
  class PaginationComponentPreview < ViewComponent::Preview
    def middle_page
      render Admin::PaginationComponent.new(pagination: Pagination.new(page: 4, per_page: 50, total: 312), url: ->(page) { "?page=#{page}" })
    end

    def first_page
      render Admin::PaginationComponent.new(pagination: Pagination.new(page: 1, per_page: 50, total: 120), url: ->(page) { "?page=#{page}" })
    end
  end
end
