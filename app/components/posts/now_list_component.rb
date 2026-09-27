module Posts
  # A "now" listing (`ContentTypes::NowUpdate#list_component`): shows only the
  # latest update (pre-flight ruling, open-types ledger) -- a whole-list
  # component rather than a per-item one is exactly what makes that possible,
  # since a per-item component would have no way to say "just the first one".
  # Ported verbatim from the old (now deleted) `content_blocks` `post_list` `_now` partial.
  class NowListComponent < ApplicationComponent
    def initialize(posts:, page:)
      @posts = posts
      @page = page
    end

    private

    attr_reader :posts, :page
  end
end
