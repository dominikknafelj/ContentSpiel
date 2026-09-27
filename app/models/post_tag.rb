class PostTag < ApplicationRecord
  belongs_to :post
  belongs_to :tag

  # `post.tags << tag` and `tag.destroy`/`post.tags.delete(tag)` write and
  # remove this join row directly, through `has_many :through` -- neither
  # touches `posts` itself, so `Post`'s own `after_save` callback (post.rb)
  # never fires for a tag change alone. A tag-filtered post_list block's
  # `lists?` reads `post.tags`, so a post's canonical page can depend on
  # exactly this row existing -- this is what re-syncs it when nothing else
  # would.
  #
  # `after_commit`, not `after_save`/`after_destroy`: a join row is written
  # inside whatever transaction its caller opened (an Avo save, a console
  # `<<`), and syncing before that transaction either commits or rolls back
  # would announce -- or act on -- a tag change that might still disappear.
  after_commit :sync_post_paths, on: [ :create, :destroy ]

  private

  # `post` is nil here when this row was destroyed as part of the post
  # itself being destroyed (`Post`'s own `dependent: :destroy`): by the time
  # this fires, after the whole transaction commits, the post row is gone, so
  # the lazily-loaded association finds nothing left to sync.
  def sync_post_paths
    PublicSite::Paths.sync(post) if post
  end
end
