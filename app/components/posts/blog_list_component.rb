module Posts
  # An ordinary blog listing (`ContentTypes::Blog#list_component`), and the
  # fallback for any content type that doesn't register its own (see
  # `Blocks::PostListComponent#list_component`). Ported verbatim from the old
  # (now deleted) `content_blocks` `post_list` `_blog` partial.
  class BlogListComponent < ApplicationComponent
    include Blocks::Contract

    contract(
      accessibility: "A plain list; each post's title is its link, and the date and the first tag are text.",
      motion: :none,
      content_edges: %i[none many long missing],
      widths: :container,
      interface: %i[posts page],
      words: [],
      limits: [
        "An empty list draws an empty ul and no words.",
        "The date is written by post_date in English month names, not in the visitor's language."
      ]
    )

    def initialize(posts:, page:)
      @posts = posts
      @page = page
    end

    private

    attr_reader :posts, :page
  end
end
