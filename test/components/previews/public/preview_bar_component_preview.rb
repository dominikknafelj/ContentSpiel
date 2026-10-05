require_relative "../preview_fixtures"

module Public
  # `Public::PreviewBarComponent` (design pass round 3): the signed-in preview
  # bar of the public site, for a draft and a live page.
  class PreviewBarComponentPreview < ViewComponent::Preview
    def draft
      render Public::PreviewBarComponent.new(record: PreviewFixtures.page(title: "About").tap { |page| page.update!(published_at: nil) }, locale: "en")
    end

    def live
      render Public::PreviewBarComponent.new(record: PreviewFixtures.page(title: "A very long title that has to be cut to one line by the stylesheet and not by Ruby"), locale: "en")
    end
  end
end
