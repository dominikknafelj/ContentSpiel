module Posts
  # An ordinary blog listing (`ContentTypes::Blog#list_component`), and the
  # fallback for any content type that doesn't register its own (see
  # `Blocks::PostListComponent#list_component`). Ported verbatim from the old
  # (now deleted) `content_blocks` `post_list` `_blog` partial.
  class BlogListComponent < ApplicationComponent
    def initialize(posts:, page:)
      @posts = posts
      @page = page
    end

    private

    attr_reader :posts, :page
  end
end
