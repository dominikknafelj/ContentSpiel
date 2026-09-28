module RichText
  # The youtube-nocookie embed for a `youtube{id}` node (design spec §3.3).
  # Markup moved verbatim from `app/views/youtube_embeds/_youtube_embed
  # .html.erb` (`YoutubeEmbed`'s own ActionText-attachment partial, kept in
  # place -- ActionText still renders through it until Task 6 retires
  # ActionText entirely) -- this component takes a bare, already-validated
  # video id instead of a `YoutubeEmbed` record, since `RichText::HtmlRenderer`
  # has a Tiptap node's `attrs.id` String to work with, not an attachable
  # model instance.
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
