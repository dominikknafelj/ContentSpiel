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
        @post.save || raise(ActiveRecord::Rollback)
      end

      return failure(@post) unless saved

      record_event(:post_saved, post: @post)
      success(@post)
    end

    private

    def assign
      # `content_type` is assigned first: `fields`/`assign_fields` below both
      # need it to know which type's schema they're casting against.
      @post.assign_attributes(@attributes.except(:published, :published_at, :tag_names, :fields))

      @post.assign_fields(@attributes[:fields], locale: Locales.default) if @attributes.key?(:fields)

      @translations.each do |locale, values|
        values = values.to_h.symbolize_keys
        Mobility.with_locale(locale) { @post.assign_attributes(values.slice(*TRANSLATED).except(:body)) }
        # `body` is a rich-text JSON document (tiptap spec §3.1), not a
        # Mobility string: a Hash (MCP after Markdown conversion, seeds) or
        # the admin's hidden-input JSON String -- `Post#assign_body` accepts
        # either and writes the jsonb `body_doc`, never the legacy ActionText
        # `body` a plain `assign_attributes(body: ...)` would still reach
        # until Task 6 removes it.
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
