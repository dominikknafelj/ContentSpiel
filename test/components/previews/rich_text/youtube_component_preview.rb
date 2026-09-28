module RichText
  # `RichText::YoutubeComponent` (design spec §3.3) -- one example, since the
  # component has exactly one state (an id) and no captionless/attached-vs-
  # not branch the way `RichText::ImageComponentPreview` has.
  class YoutubeComponentPreview < ViewComponent::Preview
    def default
      render RichText::YoutubeComponent.new(id: "dQw4w9WgXcQ")
    end
  end
end
