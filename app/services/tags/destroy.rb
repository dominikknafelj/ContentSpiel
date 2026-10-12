module Tags
  # Permanently deletes a tag (spec §5.3's "No trash" interim state, global
  # constraints), the same shape `ContentBlocks::Destroy` and
  # `Trash::Purge` use. Its join rows go with it (`Tag#has_many :post_tags,
  # dependent: :destroy`), and so does what a list that filtered by it
  # listed. The service says what it touched, read before the destroy while
  # there is still something to read it from: the pages whose list blocks
  # refer to the tag (`Tags::Listings#pages_listing`) and the posts that
  # carried it. `PublicSite::Paths.refresh` knows the rest, a post an
  # unfiltered list elsewhere now picks up included.
  #
  # While both copies hold the tag's id nothing public changes: a published
  # list and a published post go on matching by an id nobody else can be
  # given, until either is published again.
  class Destroy < ApplicationService
    include Tags::Listings

    def initialize(tag, actor: Current.actor)
      @tag = tag
      @actor = actor
    end

    # Needs `tags.manage`, like `Tags::Rename`. `tag.deleted` is recorded
    # before the destroy, in its transaction (the snapshot is the tag's last
    # state); the resync runs after it commits, as before.
    def call
      return denied("tags.manage", @tag) unless authorize!("tags.manage", @tag)

      pages = pages_listing(names: [ @tag.name ], ids: [ @tag.id ])
      carriers = @tag.post_tags.pluck(:post_id)
      destroyed = Tag.transaction do
        touch_carrying_posts(@tag)
        record_event("tag.deleted", subject: @tag)
        @tag.destroy || raise(ActiveRecord::Rollback)
      end
      return failure(@tag) unless destroyed

      PublicSite::Paths.refresh(pages: pages, posts: carriers)
      success(@tag)
    end
  end
end
