module Admin
  # `Admin::RecordHeaderComponent` (cs-studio spec §5.1): one example per
  # publish state, since the header's own available actions (Publish now,
  # Unpublish, Delete's disabled reason) all pivot on it.
  class RecordHeaderComponentPreview < ViewComponent::Preview
    def draft
      page = PreviewFixtures.root_page.children.create!(page_type: :standard, title: "Draft page #{SecureRandom.hex(4)}")
      render Admin::RecordHeaderComponent.new(page: page, locale: "en")
    end

    def scheduled
      page = PreviewFixtures.root_page.children.create!(page_type: :standard, title: "Scheduled page #{SecureRandom.hex(4)}", published_at: 1.week.from_now)
      render Admin::RecordHeaderComponent.new(page: page, locale: "en")
    end

    def live
      page = PreviewFixtures.page(title: "Live page")
      render Admin::RecordHeaderComponent.new(page: page, locale: "en")
    end

    def with_children_delete_disabled
      page = PreviewFixtures.page(title: "Parent page")
      page.children.create!(page_type: :standard, title: "Child page #{SecureRandom.hex(4)}")
      render Admin::RecordHeaderComponent.new(page: page, locale: "en")
    end
  end
end
