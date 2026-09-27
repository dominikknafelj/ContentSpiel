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
      @translations.each do |locale, values|
        Mobility.with_locale(locale) { @post.assign_attributes(values.to_h.symbolize_keys.slice(*TRANSLATED)) }
      end
      @post.assign_attributes(@attributes.except(:published, :published_at, :tag_names))
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
