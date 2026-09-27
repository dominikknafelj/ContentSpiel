module Blocks
  # A listing of posts (`BlockTypes::PostList`). Computes the same query and
  # dispatch the old (now deleted) `content_blocks` `_post_list` partial's `case
  # settings.content_type ... when ...` did, just against the registry
  # instead of a hardcoded three-way switch -- a plugin's content type gets a
  # listing for free the moment it registers a `list_component`, rather than
  # needing a new `when` branch here.
  class PostListComponent < ApplicationComponent
    def initialize(block:, page:)
      @block = block
      @page = page
    end

    # The block's `settings` are the listing's query criteria, applied by
    # `ContentBlock#listed_posts`: `Post.published` is what keeps drafts
    # (never published) and scheduled posts (a future date) out of the
    # listing while leaving them visible in the admin, and a blank
    # `content_type` means every content type. The single-post detail view
    # (`Posts::DetailComponent`, dispatched from `pages/show.html.erb`)
    # resolves through the same method, so a page lists and serves
    # permalinks for exactly the same posts.
    #
    # A blank/unknown `content_type` renders through `ContentTypes.default`
    # (blog) -- the same reading `listed_posts` already gives a blank
    # `content_type` (every type), so an unfiltered listing needs *some*
    # component to render its rows through, and the default type's is as
    # good a choice as any single one.
    def list_component
      settings = block.settings_object
      posts = block.listed_posts.order(published_at: :desc).includes(:tags)
      posts = posts.limit(settings.limit) if settings.limit.present?

      list_definition = ContentTypes.find(settings.content_type) || ContentTypes.default
      Theme.current.component_for(list_definition, :list_component).new(posts: posts, page: page)
    end

    private

    attr_reader :block, :page
  end
end
