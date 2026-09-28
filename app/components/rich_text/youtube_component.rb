module RichText
  # The youtube-nocookie embed for a `youtube{id}` node (design spec §3.3).
  # Markup moved verbatim from the retired `YoutubeEmbed` ActionText
  # attachment's partial (removed with ActionText, design spec §5) -- this
  # component takes a bare, already-validated video id, since
  # `RichText::HtmlRenderer` has a Tiptap node's `attrs.id` String to work
  # with, not an attachable model instance.
  #
  # `id` must already be exactly `RichText::YOUTUBE_ID_PATTERN`-shaped by
  # the time it reaches here -- `RichText::BuiltIns`'s `youtube` node
  # `html` block re-checks that before ever constructing this component
  # (rather than trusting `RichText::Document#validate` already ran), since
  # this component's own template only escapes what it's given, it doesn't
  # validate it.
  class YoutubeComponent < ApplicationComponent
    def initialize(id:)
      @id = id
    end

    private

    attr_reader :id
  end
end
