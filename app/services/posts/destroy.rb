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
  class Destroy < ApplicationService
    def initialize(post, actor: Current.actor)
      @post = post
      @actor = actor
    end

    def call
      authorize!(:destroy, @post)

      return failure(@post) unless @post.destroy

      record_event(:post_destroyed, post: @post)
      success(@post)
    end
  end
end
