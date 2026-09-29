module Posts
  # Permanently removes one post (spec §7's "No trash" interim state, global
  # constraints). Unlike `Pages::Destroy`, there is no "still has children"
  # rule to enforce -- a post has no descendants of its own, and its
  # `has_many ... dependent: :destroy` associations (`post_tags`,
  # `post_relations`, `inverse_post_relations`) already clean up after it --
  # so this is a plain `destroy` wrapped in the same `ApplicationService
  # ::Result` shape every other write goes through (global constraints'
  # "writes go only through services"), added here for `Admin::
  # PostsController#destroy` (cs-studio spec §5.2) the same way `ContentBlocks
  # ::Destroy` was added for the block card's own Delete.
  #
  # Needs `posts.delete` on the post (access-control design spec §3.3).
  # `post.deleted` is recorded *before* the destroy, in the same
  # transaction: its snapshot is the post's last state, tags and relations
  # included, which are gone once the destroy has run -- and a refused
  # destroy rolls the event back with it.
  class Destroy < ApplicationService
    def initialize(post, actor: Current.actor)
      @post = post
      @actor = actor
    end

    def call
      return denied("posts.delete", @post) unless authorize!("posts.delete", @post)

      destroyed = Post.transaction do
        record_event("post.deleted", subject: @post)
        @post.destroy || raise(ActiveRecord::Rollback)
      end

      return failure(@post) unless destroyed

      success(@post)
    end
  end
end
