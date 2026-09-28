module Admin
  # The post editor's related-posts picker (design spec §6.1, Task 9):
  # search, add, remove. Writes through `Posts::Save`'s `related_post_ids`
  # as part of the post form's own autosave -- no endpoint of its own.
  #
  # The hidden-field contract (see `Posts::Save#assign_related_posts`):
  # this section always renders one blank `post[related_post_ids][]`
  # sentinel ahead of one hidden entry per related post. The sentinel is
  # what makes "the picker is on the page and currently empty" (key present,
  # `[""]` -> clear) distinguishable from "this PATCH has nothing to say
  # about relations" (key absent -> leave alone): a form with every entry
  # removed still submits the key, and a form that never rendered this
  # section (or any other client) can't clear relations by accident.
  #
  # Only *forward* relations (`post.related_posts`, rows where this post is
  # `post_id`) are editable here -- they're what `related_post_ids`
  # replaces. A post that points at this one is listed separately, read
  # only ("Also related from"), since that row belongs to the other post's
  # own list; relations read as undirected everywhere else
  # (`Post#all_related_posts`).
  #
  # Searching goes to `<admin>/link_targets?type=post` (the internal-link
  # picker's own endpoint, `Admin::LinkTargetsController`), built through
  # its route helper, never a hand-written path -- which only offers posts
  # the actor may read.
  #
  # Nor does this list disclose a post the actor can't read (access-control
  # design spec §3.3): a forward relation to one keeps its row and hidden
  # entry -- dropping it would make the next autosave delete a relation the
  # editor never saw -- but shows no title or link; an "Also related from"
  # post they can't read is left out.
  class RelatedPostsComponent < AdminComponent
    ID_PREFIX = "post"
    UNREADABLE_TITLE = "A post you can't open"

    def initialize(post:, locale:, url_options: {}, errors: [])
      @post = post
      @locale = locale
      @url_options = url_options
      @errors = errors
    end

    def html_name = "#{ID_PREFIX}[related_post_ids][]"

    def search_id = "#{ID_PREFIX}-related_post_ids"

    def errors_id = Admin::FieldComponent.error_id(ID_PREFIX, "related_post_ids")

    def search_url = helpers.admin_link_targets_path(type: "post")

    def editor_path(record) = helpers.admin_post_path(record, **url_options)

    def related = post.related_posts.order(:id).to_a

    def related_from
      readable(Post.where(id: PostRelation.where(related_post_id: post.id).select(:post_id))).order(:id).to_a
    end

    def readable?(record) = readable_related_ids.include?(record.id)

    def title_for(record) = Locales.read(record, :title, locale: locale).presence || "Untitled"

    private

    attr_reader :post, :locale, :url_options, :errors

    def readable(relation) = AccessControl.scope(Current.actor, "posts.read", relation)

    def readable_related_ids
      @readable_related_ids ||= readable(post.related_posts).pluck(:id).to_set
    end
  end
end
