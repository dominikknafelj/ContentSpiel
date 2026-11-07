module Posts
  # A resume listing (`ContentTypes::ResumeEntry#list_component`). Ported
  # verbatim from the old (now deleted) `content_blocks` `post_list` `_resume` partial.
  class ResumeListComponent < ApplicationComponent
    include Blocks::Contract

    contract(
      accessibility: "A plain list; each entry's title is its link, and the period, the company and the role are text.",
      motion: :none,
      content_edges: %i[none many long missing],
      widths: :from_container,
      interface: %i[posts page],
      words: [],
      limits: [
        "An empty list draws an empty ul and no words.",
        "The role's words (ContentTypes::ResumeEntry::ROLE_TYPES) and the period's \"now\" (resume_period) are English literals, not public keys."
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
