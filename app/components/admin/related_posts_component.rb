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
  # The field itself is `Admin::ChipInputComponent` (design pass round 2):
  # each related post a chip with its content-type dot, its title and
  # "· Draft" / "· Scheduled" when it isn't live. This component keeps what
  # is specific to relations -- which posts those are, the hidden count and
  # the read-only "Also related from" line.
  #
  # Searching goes to `<admin>/link_targets?type=post` (the internal-link
  # picker's own endpoint, `Admin::LinkTargetsController`), built through
  # its route helper, never a hand-written path -- which only offers posts
  # the actor may read.
  #
  # Nor does this list disclose a post the actor can't read (access-control
  # design spec §3.3, "not found, not forbidden"): a forward relation to one
  # is left out entirely -- no row, no hidden entry, so not even its id
  # reaches the page -- and only counted ("+N related posts you can't
  # open"). Omitting it from the submitted list is safe because
  # `Posts::Save#assign_related_posts` never removes a relation to a post
  # the actor can't read: it's outside their say. An "Also related from"
  # post they can't read is left out the same way.
  class RelatedPostsComponent < AdminComponent
    ID_PREFIX = "post"

    def initialize(post:, locale:, url_options: {}, errors: [])
      @post = post
      @locale = locale
      @url_options = url_options
      @errors = errors
    end

    def html_name = "#{ID_PREFIX}[related_post_ids][]"

    def search_id = "#{ID_PREFIX}-related_post_ids"

    def errors_id = Admin::FieldComponent.error_id(ID_PREFIX, "related_post_ids")

    # `locale:` so the rows' titles are in the language being edited.
    def search_url = helpers.admin_link_targets_path(type: "post", locale: locale)

    def chips
      related.map do |record|
        { value: record.id.to_s, label: title_for(record), hint: (record.status.humanize unless record.live?), dot: dot_class(record) }
      end
    end

    def hidden_note
      hidden = hidden_related_count
      "+#{pluralize(hidden, 'related post')} you can’t open (kept)" if hidden.positive?
    end

    def dot_class(record)
      definition = ::ContentTypes.find(record.content_type)
      definition && Admin::ContentTypeDotComponent.new(content_type: record.content_type).mark_class(definition.colour_index)
    end

    delegate :pluralize, to: :helpers

    def editor_path(record) = helpers.admin_post_path(record, **url_options)

    def related = readable(post.related_posts).order(:id).to_a

    # Forward relations to posts the actor can't read: counted, never shown.
    # A trashed post isn't one of them (trash spec §5.1): it's hidden from
    # everyone, not from this actor, and "+1 you can't open" would suggest
    # otherwise. Its relation row stays (`Posts::Save#unreadable_related_ids`
    # keeps it on save), so it's back as soon as the post is restored.
    def hidden_related_count = post.related_posts.kept.count - related.size

    def related_from
      readable(Post.where(id: PostRelation.where(related_post_id: post.id).select(:post_id))).order(:id).to_a
    end

    def title_for(record) = Locales.read(record, :title, locale: locale).presence || "Untitled"

    private

    attr_reader :post, :locale, :url_options, :errors

    def readable(relation) = AccessControl.scope(Current.actor, "posts.read", relation)
  end
end
