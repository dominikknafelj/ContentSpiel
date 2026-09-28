module Posts
  # Creates or updates a post (spec §7.2). Translations arrive per locale so an
  # admin form can save every language tab at once; publishing follows the
  # rules 8a established for MCP.
  class Save < ApplicationService
    TRANSLATED = %i[title slug excerpt body].freeze

    def initialize(post = Post.new, attributes: {}, translations: {}, actor: Current.actor)
      @post = post
      @attributes = attributes.to_h.symbolize_keys
      @translations = translations.to_h
      # Not read anywhere yet -- the attachment point for `authorize!`/
      # `record_event` once those grow teeth (sub-project 5).
      @actor = actor
    end

    def call
      authorize!(:save, @post)

      saved = Post.transaction do
        assign
        (@post.save && assign_related_posts) || raise(ActiveRecord::Rollback)
      end

      return failure(@post) unless saved

      record_event(:post_saved, post: @post)
      success(@post)
    end

    private

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
