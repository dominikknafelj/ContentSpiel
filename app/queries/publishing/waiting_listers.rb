module Publishing
  # The published or scheduled pages whose ROWS hold a list block that lists
  # `post` while their changes are unpublished: the list is there, in the
  # editor, and the site does not show it yet. For the post editor's line
  # under the title of a post that has no address: "add a post list block
  # for this type" would be wrong advice when someone has added it and not
  # published the page.
  #
  # Rows on purpose, on both sides (the page's blocks and the post's tags as
  # they are being edited): this is CS Studio saying what is waiting, not
  # the site saying what is listed (`Publishing::Listing` is that). Trashed
  # pages are left out here, at the narrowing point.
  #
  # Asked only for a post that has no address (one statement more, and one
  # for the blocks of the few pages that have unpublished changes).
  class WaitingListers
    def self.for(post)
      pages = Page.kept.with_unpublished_changes
      ContentBlock.listing.where(owner_type: "Page", owner_id: pages.select(:id)).includes(:owner)
        .select { |block| block.lists?(post) }.map(&:owner).uniq
    end
  end
end
