module Posts
  # Creates or updates a post (spec §7.2). Translations arrive per locale so an
  # admin form can save every language tab at once; publishing follows the
  # rules 8a established for MCP.
  #
  # Permissions (access-control design spec §3.3), checked in two passes:
  #
  # 1. Before anything is assigned, against the post as stored: `posts.edit`
  #    to touch an existing post at all, plus `posts.publish` when it's
  #    already published (live or scheduled). The second is the spec §8
  #    interim rule: autosave writes live content straight to the public
  #    site (there are no pending revisions until Phase 3), so editing a
  #    published post *is* publishing, and needs the same right. A
  #    scheduled post counts too -- it will go live with whatever it says
  #    by then, without anyone with `publish` having seen it.
  # 2. After assigning, inside the transaction, against the post as it
  #    would be saved -- the only point where a create's content type (the
  #    `content_types` scope), a changed content type or author, and a
  #    change of publish state are known:
  #    - a new post needs `posts.create` for its content type, with
  #      `author_id` set to the actor's user first, so an `own`-scoped
  #      create matches;
  #    - a changed `content_type` or `author_id` needs `posts.edit` on the
  #      post as it would be saved too -- which is what makes "changing the
  #      author needs `posts.edit` without an `own` scope" hold: an `own`
  #      grant can't match a post whose new author isn't the actor, and the
  #      first pass already refused a post they didn't author. A new post
  #      given someone else's `author_id` is checked the same way;
  #    - any change to `published_at` (publishing, unpublishing,
  #      scheduling) needs `posts.publish`.
  #    A refusal here rolls the transaction back (tag rows `assign_tags`
  #    wrote included) and only then records `access.denied`, outside it,
  #    so the denial itself survives the rollback.
  class Save < ApplicationService
    TRANSLATED = %i[title slug excerpt body].freeze

    def initialize(post = Post.new, attributes: {}, translations: {}, actor: Current.actor)
      @post = post
      @attributes = attributes.to_h.symbolize_keys
      @translations = translations.to_h
      @actor = actor
    end

    def call
      if @post.persisted?
        return denied("posts.edit", @post) unless authorize!("posts.edit", @post)
        return denied("posts.publish", @post) if @post.published_at.present? && !authorize!("posts.publish", @post)
      end

      refused = nil
      saved = Post.transaction do
        related_before = related_state
        assign
        refused = refusal_after_assign
        raise ActiveRecord::Rollback if refused

        (@post.save && assign_related_posts) || raise(ActiveRecord::Rollback)
        record_events(related_before)
        true
      end

      return denied(refused, @post) if refused
      return failure(@post) unless saved

      success(@post)
    end

    private

    # The second pass (see the class comment). Returns the key that was
    # refused, or nil.
    def refusal_after_assign
      if @post.new_record?
        @post.author_id ||= actor_user&.id
        return "posts.create" unless authorize!("posts.create", @post)
        return "posts.edit" if foreign_author? && !authorize!("posts.edit", @post)
      elsif (@post.content_type_changed? || @post.author_id_changed?) && !authorize!("posts.edit", @post)
        return "posts.edit"
      end

      "posts.publish" if @post.published_at_changed? && !authorize!("posts.publish", @post)
    end

    def foreign_author? = @post.author_id.present? && @post.author_id != actor_user&.id

    # Tags and relations are join rows, invisible to `saved_changes`, so
    # their before/after is captured by hand for the event's
    # `field_changes` -- only when this call was asked to change them.
    def related_state
      state = {}
      state["tag_names"] = tag_names if @attributes.key?(:tag_names)
      state["related_post_ids"] = related_post_ids if @attributes.key?(:related_post_ids)
      state
    end

    # Queried, never loaded into the associations: `assign_related_posts`
    # reads `@post.post_relations` afresh, and a copy loaded here would be
    # stale by then.
    def tag_names = @post.new_record? ? [] : Tag.joins(:post_tags).where(post_tags: { post_id: @post.id }).pluck(:name).sort

    def related_post_ids = @post.new_record? ? [] : PostRelation.where(post_id: @post.id).pluck(:related_post_id).sort

    # One event for the save (`post.created`/`post.updated`) and, when
    # `published_at` changed, one for the publish state -- `post.published`,
    # `post.unpublished` or `post.scheduled` -- which never coalesces, so a
    # publish stays findable on its own however much editing surrounds it.
    # An update that changed nothing but the publish state (the header's
    # Publish button) records only the latter; one that changed nothing at
    # all records nothing.
    def record_events(related_before)
      changes = Audit::Snapshot.field_changes_for(@post)
      related_before.each do |field, before|
        after = send(field)
        changes[field] = [ before, after ] unless before == after
      end

      if @post.previously_new_record?
        record_event("post.created", subject: @post, field_changes: changes)
        record_event(publish_action, subject: @post, field_changes: changes.slice("published_at")) if @post.published_at
      else
        publishing = changes.slice("published_at")
        rest = changes.except("published_at")
        record_event("post.updated", subject: @post, field_changes: rest) if rest.any?
        record_event(publish_action, subject: @post, field_changes: publishing) if publishing.any?
      end
    end

    def publish_action
      if @post.published_at.nil? then "post.unpublished"
      elsif @post.published_at > Time.current then "post.scheduled"
      else "post.published"
      end
    end

    def assign
      # `content_type` is assigned first: `fields`/`assign_fields` below both
      # need it to know which type's schema they're casting against.
      @post.assign_attributes(@attributes.except(:published, :published_at, :tag_names, :fields, :related_post_ids))

      @post.assign_fields(@attributes[:fields], locale: Locales.default) if @attributes.key?(:fields)

      @translations.each do |locale, values|
        values = values.to_h.symbolize_keys
        Mobility.with_locale(locale) { @post.assign_attributes(values.slice(*TRANSLATED).except(:body)) }
        # `body` is a rich-text JSON document (tiptap spec §3.1), not a
        # Mobility string: a Hash (MCP after Markdown conversion, seeds) or
        # the admin's hidden-input JSON String -- `Post#assign_body` accepts
        # either, parses the String, and refuses a "nothing" value that a
        # plain `assign_attributes(body: ...)` would write straight through
        # (Mobility turns it into nil, deleting the locale's document).
        @post.assign_body(values[:body], locale: locale) if values.key?(:body)
        @post.assign_fields(values[:fields], locale: locale) if values.key?(:fields)
      end

      assign_publishing
      assign_tags if @attributes.key?(:tag_names)
    end

    # `published_at` schedules explicitly and wins; `published: true` makes a
    # draft or scheduled post live now but keeps a live post's date (8a);
    # `published: false` unpublishes; absent leaves it alone.
    def assign_publishing
      if @attributes.key?(:published_at)
        @post.published_at = @attributes[:published_at]
      elsif @attributes[:published] == true
        @post.published_at = Time.current unless @post.live?
      elsif @attributes[:published] == false
        @post.published_at = nil
      end
    end

    # `related_post_ids` (design spec §6.1) is the *complete* list of this
    # post's forward relations (`post_relations`, the rows where this post
    # is `post_id`): named ids are kept or added, every other forward row is
    # removed. The key's presence is the whole contract -- absent means
    # "leave the relations alone" (MCP, the header's publish buttons, any
    # PATCH that didn't come from the picker), `[]` means "clear them". The
    # admin picker (`Admin::RelatedPostsComponent`) always submits a blank
    # sentinel entry alongside its real ones, so the key is present exactly
    # when the picker itself was on the page.
    #
    # Runs *after* `@post.save`, still inside `call`'s own transaction: a new
    # post has no id to hang a relation on before that, and returning false
    # here rolls the post's own save back with it, so an unknown id changes
    # nothing at all -- not the relations, not the title saved alongside.
    # `errors.add` comes after `save` for the same reason: `save`'s own
    # `valid?` would clear an error added any earlier.
    #
    # - Blank entries (the sentinel) and the post itself are ignored -- a
    #   post can't relate to itself (`PostRelation#not_self_referential`),
    #   and a picker that briefly offered it shouldn't turn that into a
    #   failed save.
    # - An id that isn't an integer or names no post fails the whole save
    #   with an error on `related_post_ids`, rather than being dropped
    #   silently: the editor asked for a relation that can't exist, and
    #   saying so beats a picker that quietly loses an entry.
    # - An id that already points back at this post (a reverse row,
    #   `post_id: other, related_post_id: this`) is already related --
    #   relations read as undirected (`Post#all_related_posts`) -- so it's
    #   skipped rather than tripping `PostRelation#not_duplicate_reverse_
    #   pair`. The reverse row itself belongs to the other post's own list
    #   and is never removed from here.
    def assign_related_posts
      return true unless @attributes.key?(:related_post_ids)

      raw = Array(@attributes[:related_post_ids]).map(&:to_s).map(&:strip).compact_blank
      ids = raw.map { |value| Integer(value, 10, exception: false) }
      known = Post.where(id: ids.compact).pluck(:id)

      if ids.any?(&:nil?) || (ids.compact - known).any?
        @post.errors.add(:related_post_ids, "include posts that don't exist")
        return false
      end

      wanted = ids.uniq - [ @post.id ] - PostRelation.where(related_post_id: @post.id).pluck(:post_id)
      @post.post_relations.where.not(related_post_id: wanted).destroy_all
      (wanted - @post.post_relations.pluck(:related_post_id)).each do |id|
        relation = @post.post_relations.create(related_post_id: id)
        next if relation.persisted?

        relation.errors.full_messages.each { |message| @post.errors.add(:related_post_ids, message) }
        return false
      end

      true
    end

    # `@post.tags =` on an already-persisted post writes the join rows
    # immediately (has_many :through, not autosaved on `save`), but that
    # write still lands inside the same `Post.transaction` block `call`
    # wraps `assign` in, so a subsequent validation failure's
    # `ActiveRecord::Rollback` undoes it along with everything else --
    # confirmed by the "invalid input... nothing saved" test, which would
    # otherwise leave an orphaned Tag/PostTag behind.
    def assign_tags
      @post.tags = Array(@attributes[:tag_names]).map(&:to_s).map(&:strip).compact_blank.uniq(&:downcase).map do |name|
        Tag.where("LOWER(name) = ?", name.downcase).first || Tag.new(name: name.downcase)
      end
    end
  end
end
