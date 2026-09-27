module Posts
  # A resume listing (`ContentTypes::ResumeEntry#list_component`). Ported
  # verbatim from the old (now deleted) `content_blocks` `post_list` `_resume` partial.
  class ResumeListComponent < ApplicationComponent
    def initialize(posts:, page:)
      @posts = posts
      @page = page
    end

    private

    attr_reader :posts, :page
  end
end
