module Posts
  # One post, rendered where its listing would otherwise be
  # (`ContentTypeDefinition#detail_component`, shared by every built-in
  # content type). Ported verbatim from the old
  # (now deleted) `content_blocks` `_post_list_detail` partial -- `title`/`body` read through
  # the request's locale (`PagesController`/`PreviewController` set it for the
  # whole request via `PublicPageRendering`), so a German URL renders the
  # German translation.
  class DetailComponent < ApplicationComponent
    include Blocks::Contract

    contract(
      accessibility: "An article whose h1 is the post's title, with its date and excerpt as text, the body as rich text and the tags as one line of text after a \"Tagged\" label.",
      motion: :none,
      content_edges: %i[long short missing],
      widths: :container,
      interface: %i[post],
      words: %w[public.site.tagged],
      limits: [
        "The tags are plain text, never links.",
        "The date is written by post_date in English month names, not in the visitor's language."
      ]
    )

    def initialize(post:)
      @post = post
    end

    private

    attr_reader :post
  end
end
