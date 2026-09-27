module Posts
  # One post, rendered where its listing would otherwise be
  # (`ContentTypeDefinition#detail_component`, shared by every built-in
  # content type). Ported verbatim from the old
  # (now deleted) `content_blocks` `_post_list_detail` partial -- `title`/`body` read through
  # the request's locale (`PagesController`/`PreviewController` set it for the
  # whole request via `PublicPageRendering`), so a German URL renders the
  # German translation.
  class DetailComponent < ApplicationComponent
    def initialize(post:)
      @post = post
    end

    private

    attr_reader :post
  end
end
