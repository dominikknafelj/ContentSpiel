module BlockTypes
  # A listing of posts (spec §3.1, §6): which posts it lists is its settings'
  # content type (blank = every content type) and tag; `limit` trims display
  # only. Carries the `lists_posts` capability, which is what canonical URLs
  # and the resolver's listing fallback look for.
  module PostList
    def self.register
      BlockTypes.register :post_list do |t|
        t.label "Post list"
        t.field :content_type, :content_type
        t.field :tag, :string
        t.field :limit, :integer, min: 1
        t.capability :lists_posts
        t.component Blocks::PostListComponent
      end
    end

    # The published posts a post_list block with these settings is
    # responsible for: its listing renders them (newest first, trimmed to
    # `settings.limit`) and its page serves a permalink for each of them.
    # Moved here verbatim (with its comments) from the old
    # `ContentBlock#listed_posts` -- only the source of `content_type`/`tag`
    # changed, from the raw `settings` hash to the typed `settings_object`.
    #
    # An absent `content_type` means "every content type" -- the same
    # reading `lists?` below is written against, and the one an editor gets
    # by leaving the field empty in the admin. It must therefore never reach
    # `where`: `posts.content_type` is NOT NULL, so `where(content_type: nil)`
    # compiles to `content_type IS NULL` and the block silently lists nothing
    # at all.
    #
    # "Every content type" still means "every *registered* content type"
    # (spec §4.2: "a post of an unknown type has no public URL") -- a post
    # whose stored `content_type` names a removed plugin or a typo has no
    # `definition` and so no schema to render its listing row against, let
    # alone a canonical URL for `post_url_path` to link to. Always scoping to
    # `ContentTypes.names`, not just when `settings.content_type` is blank,
    # is what keeps a *filtered* listing consistent with the same rule: a
    # filter naming a real type can never accidentally let a stale-typed post
    # through some other path.
    def self.listed_posts(settings, include_unpublished: false)
      scope = include_unpublished ? Post.all : Post.published
      scope = scope.where(content_type: ContentTypes.names)
      content_type = settings.content_type
      scope = scope.where(content_type: content_type) if content_type.present?

      # Tag names are matched case-insensitively: editors type "Rails" for a
      # tag stored as "rails". Trim to handle pasted tags with surrounding
      # whitespace.
      tag = settings.tag.to_s.strip
      if tag.present?
        scope = scope.where(id: PostTag.joins(:tag).where("LOWER(tags.name) = ?", tag.downcase).select(:post_id))
      end

      scope
    end

    # Whether a post_list block with these settings would list `post`,
    # ignoring publication: the same content-type-and-tag criteria
    # `listed_posts` applies, minus its `Post.published`/`Post.all` scope.
    # `PublicSite::Paths.canonical_page` (spec §5.3) needs this per-post
    # rather than per-scope test to collect every candidate listing for a
    # post -- it then ranks them by the listing page's publication, the
    # block's specificity and tree order itself; the *post's* own publication
    # is the resolver's to gate (spec §6.3). Kept deliberately in lockstep
    # with `listed_posts` above: any criteria change there has to land here
    # too, or a post's listing and its canonical URL would disagree about
    # which page is responsible for it.
    #
    # `ContentBlock#lists?` already checks the `lists_posts` capability
    # before delegating here, so unlike the method this replaced, there is
    # no `post_list?` guard of its own -- a single listing type makes that
    # redundant; a second one would move this behaviour onto the definition
    # itself (`t.lists_posts_with ...`) instead of a capability-wide
    # dispatch.
    def self.lists?(settings, post)
      return false if post.definition.nil?
      return false if settings.content_type.present? && settings.content_type != post.content_type

      tag = settings.tag.to_s.strip
      tag.blank? || post.tags.any? { |t| t.name.downcase == tag.downcase }
    end
  end
end
