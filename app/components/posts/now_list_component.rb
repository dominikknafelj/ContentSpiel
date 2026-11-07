module Posts
  # A "now" listing (`ContentTypes::NowUpdate#list_component`): shows only the
  # latest update (pre-flight ruling, open-types ledger) -- a whole-list
  # component rather than a per-item one is exactly what makes that possible,
  # since a per-item component would have no way to say "just the first one".
  # Ported verbatim from the old (now deleted) `content_blocks` `post_list` `_now` partial.
  class NowListComponent < ApplicationComponent
    include Blocks::Contract

    contract(
      accessibility: "The latest post's body beside two text lines, \"Now\" and its date; nothing takes focus but the body's links.",
      motion: :none,
      content_edges: %i[none long],
      widths: :from_container,
      interface: %i[posts page],
      words: [],
      limits: [
        "It draws the latest post only, and nothing without one.",
        "\"Now\" and \"Updated\" are English literals in the template, not public keys, and the date's month is English."
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
