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
  #    by then, without anyone with `publish` having seen it. A call that
  #    asks for nothing but a publish-state change needs `posts.publish`
  #    alone instead (`#publish_only?`).
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
  #
  # Every save refreshes the post's `media_usages` rows for its body images
  # (media library design spec §5.1). An image deleted between the body's
  # existence check and that write fails the save as "has an image that
  # doesn't exist" (`Media::Choosing#vanished_media_failure`), not a 500.
  class Save < ApplicationService
    include Media::Choosing

    TRANSLATED = %i[title slug excerpt body].freeze
    # The attributes a publish-only call may carry (`#publish_only?`).
    PUBLISH_STATE = %i[published published_at].freeze

    def initialize(post = Post.new, attributes: {}, translations: {}, actor: Current.actor)
      @post = post
      @attributes = attributes.to_h.symbolize_keys
      @translations = translations.to_h
      @actor = actor
    end

    def call
      if publish_only?
        return denied("posts.publish", @post) unless authorize!("posts.publish", @post)
      elsif @post.persisted?
        return denied("posts.edit", @post) unless authorize!("posts.edit", @post)
        return denied("posts.publish", @post) if @post.published_at.present? && !authorize!("posts.publish", @post)
      end

      refused = nil
      # `requires_new`: see `Pages::Save` -- a nested call's FK refusal
      # (rescued below) mustn't abort the caller's transaction.
      saved = Post.transaction(requires_new: true) do
        related_before = related_state
        assign
        refused = refusal_after_assign
        raise ActiveRecord::Rollback if refused

        (@post.save && tags_valid? && assign_related_posts) || raise(ActiveRecord::Rollback)
        touch_for_join_rows(related_before)
        # The body's `image` nodes, every locale (media library design spec
        # §5.1) -- recomputed from the saved post, so an image removed from
        # one locale's body loses exactly that locale's row.
        Media::UsageIndex.refresh(@post)
        # The post's stored translation state (`translation_states`).
        Translations::StateIndex.refresh(@post)
        record_events(related_before)
        true
      end

      if refused
        discard_refused_changes
        return denied(refused, @post)
      end
      return failure(@post) unless saved

      success(@post)
    rescue ActiveRecord::InvalidForeignKey => e
      vanished_media_failure(e, @post, nil, nil)
    end

    private

    # Tags and related posts are join rows: changing only those saves no
    # column of the post, so its `updated_at` would not move -- and
    # `updated_at` is the base every editor's autosave form carries (a stale
    # base is refused, `Admin::AutosaveResponses#refuse_stale_autosave`).
    # Left alone, another editor's tag-only change would not make a stale
    # form's next save a 409: it would silently revert the tags. Touched here,
    # inside the same transaction, only when a join set really changed (a
    # no-op resend of the same tags moves nothing) and only if the save did
    # not already move it.
    def touch_for_join_rows(related_before)
      return if @post.saved_change_to_updated_at?
      return if related_state == related_before

      @post.touch
    end

    # Publishing, unpublishing and scheduling need `posts.publish` (design
    # spec §3.3), not `posts.edit` as well (final fix wave, Important 1):
    # a call on a stored record whose only request is the publish state --
    # `published`/`published_at` and nothing else, no translation values
    # (MCP's `update_post(published:)` sends an empty per-locale hash),
    # no other attribute -- is judged on `publish` alone, so a
    # "Publishers" group (read + publish) can use the header's buttons.
    # Anything more keeps the ordinary rules above: pass 1's edit (+
    # publish when already published), and pass 2's publish check on the
    # new `published_at`, which runs here too and is what actually guards
    # the change.
    def publish_only?
      @post.persisted? && @attributes.any? && (@attributes.keys - PUBLISH_STATE).empty? &&
        @translations.values.all? { |values| values.to_h.empty? }
    end

    # The second pass (see the class comment). Returns the key that was
    # refused, or nil.
    def refusal_after_assign
      if @post.new_record?
        @post.author_id ||= actor_user&.id
        return "posts.create" unless authorize!("posts.create", @post)
        return "posts.edit" if foreign_author? && !authorize!("posts.edit", @post)
      elsif @post.content_type_changed? || @post.author_id_changed?
        return "posts.edit" unless authorize!("posts.edit", @post)
        # The published-edit rule (pass 1) again, on the new state: pass 1
        # only proved `posts.publish` for the post as stored. A publish
        # grant scoped to `blog`, or to `own`, must not let a live blog post
        # become a live `resume_entry`, or a live post of mine become a
        # live post of someone else's.
        return "posts.publish" if @post.published_at.present? && !authorize!("posts.publish", @post)
      end

      "posts.publish" if @post.published_at_changed? && !authorize!("posts.publish", @post)
    end

    # After a pass-2 refusal the transaction has rolled back, but the
    # in-memory post still holds the refused values -- the attacker's
    # title would become the `access.denied` row's `subject_label`, and the
    # refused tags would linger in `@post.tags`. A persisted post is
    # reloaded to what's stored; a new one only has its join associations
    # reset (there's nothing stored to go back to, and it's no subject).
    def discard_refused_changes
      if @post.persisted?
        @post.reload
      else
        %i[tags post_tags].each { |name| @post.association(name).reset }
      end
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
    # removed -- except relations to posts the actor can't read, which are
    # always kept (`#unreadable_related_ids`). The key's presence is the
    # whole contract -- absent means "leave the relations alone" (MCP, the
    # header's publish buttons, any PATCH that didn't come from the
    # picker), `[]` means "clear the ones you can see". The
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

      if ids.any?(&:nil?) || (ids.compact - known).any? || unreadable_additions?(ids.compact)
        @post.errors.add(:related_post_ids, "include posts that don't exist")
        return false
      end

      wanted = ids.uniq - [ @post.id ] - PostRelation.where(related_post_id: @post.id).pluck(:post_id)
      @post.post_relations.where.not(related_post_id: wanted + unreadable_related_ids).destroy_all
      (wanted - @post.post_relations.pluck(:related_post_id)).each do |id|
        relation = @post.post_relations.create(related_post_id: id)
        next if relation.persisted?

        relation.errors.full_messages.each { |message| @post.errors.add(:related_post_ids, message) }
        return false
      end

      true
    end

    # Existing forward relations to posts the actor can't read. They're
    # outside the actor's say (access-control design spec §3.3): kept
    # whatever the submitted list contains -- the admin picker never
    # renders them (`Admin::RelatedPostsComponent`), so they're never in
    # it, and `[]` clears only the readable ones. A relation to a trashed
    # post counts as unreadable here too (the scope is kept-only), so saving
    # the list never drops it and restoring the post brings it back.
    def unreadable_related_ids
      forward = Post.where(id: PostRelation.where(post_id: @post.id).select(:related_post_id))
      forward.pluck(:id) - AccessControl.scope(actor, "posts.read", forward).pluck(:id)
    end

    # A newly added relation must point at a post the actor may read
    # (access-control design spec §3.3, "Not found, not forbidden"):
    # otherwise a forged `related_post_ids` would link -- and on the public
    # site, list -- a post outside their scope, and the error would confirm
    # it exists. So an unreadable id is refused exactly like an unknown
    # one. Relations that already exist (either direction) are kept as
    # they are: an editor who can't read one mustn't lose it just by
    # saving the list back.
    def unreadable_additions?(ids)
      existing = PostRelation.where(post_id: @post.id).pluck(:related_post_id) +
        PostRelation.where(related_post_id: @post.id).pluck(:post_id)
      added = ids.uniq - existing - [ @post.id ]
      return false if added.empty?

      AccessControl.scope(actor, "posts.read", Post.where(id: added)).count < added.size
    end

    # `@post.tags =` on an already-persisted post writes the join rows
    # immediately (has_many :through, not autosaved on `save`), but that
    # write still lands inside the same `Post.transaction` block `call`
    # wraps `assign` in, so a subsequent validation failure's
    # `ActiveRecord::Rollback` undoes it along with everything else --
    # confirmed by the "invalid input... nothing saved" test, which would
    # otherwise leave an orphaned Tag/PostTag behind.
    #
    # Names are normalised the way the chip input shows them: inner runs of
    # whitespace collapse to one space, case folds (a tag is stored
    # lower-case) and a name that differs only by case is one tag. A name
    # `Tag` would refuse (too long) is not assigned -- `tags_valid?` reports
    # it after the save, as a failure on `tag_names`, which rolls the whole
    # save back like a refused related post does.
    def assign_tags
      @refused_tag_names = []
      names = Array(@attributes[:tag_names]).map { |name| name.to_s.squish }.compact_blank.uniq(&:downcase)
      @refused_tag_names = names.select { |name| name.length > Tag::MAX_NAME_LENGTH }
      return if @refused_tag_names.any?

      @post.tags = names.map do |name|
        Tag.where("LOWER(name) = ?", name.downcase).first || Tag.new(name: name.downcase)
      end
    end

    # Runs after `@post.save` (which clears errors added before it): names
    # `assign_tags` refused, each in words so the field's error slot says
    # which one.
    def tags_valid?
      Array(@refused_tag_names).each do |name|
        @post.errors.add(:tag_names, "include “#{name.truncate(24)}”, which is longer than #{Tag::MAX_NAME_LENGTH} characters")
      end
      Array(@refused_tag_names).empty?
    end
  end
end
