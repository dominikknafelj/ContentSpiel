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
        t.theme_methods :block, :page, :list_component
        t.summary ->(block, locale:) { PostList.summary(block, locale: locale) }
        # The one type whose sample leaves a field empty: `tag` (the smoke
        # test names it in UNFILLED_FIELDS; the canary's own "ruby" list
        # compares it). A sample makes no posts: the tests that draw it
        # create the posts it lists.
        t.sample settings: { "content_type" => "blog", "limit" => 5 }, shows: [ "content-block--post-list" ]
      end
    end

    # The tile's line of a closed post list (block types spec, decision 8):
    # the content type it lists, or "All posts", then its tag. A content
    # type that is no longer registered reads as its stored name, as the
    # block card's own field shows it; a block with no settings is "All
    # posts".
    def self.summary(block, locale:)
      settings = block.settings_object(locale: locale)
      type = settings&.content_type.presence
      tag = settings&.tag.presence

      [ (type ? [ :text, ContentTypes.find(type)&.label || type ] : [ :word, :any_type ]),
        *([ [ :text, " · " ], [ :word, :tag, { name: tag } ] ] if tag) ]
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
      # Never a trashed post (trash spec §5.2), in preview or not: it has
      # no URL to link to, and a listing is exactly where it would leak.
      scope = include_unpublished ? Post.kept : Post.published.kept
      scope = scope.where(content_type: ContentTypes.names)
      content_type = settings.content_type
      scope = scope.where(content_type: content_type) if content_type.present?

      # Tag names are matched case-insensitively: editors type "Rails" for a
      # tag stored as "rails". Trim to handle pasted tags with surrounding
      # whitespace.
      tag = settings.tag.to_s.strip
      if tag.present?
        scope = scope.where(id: PostTag.joins(:tag).merge(Tag.named(tag)).select(:post_id))
      end

      scope
    end

    # The same criteria for a caller that holds a post's stored type and its
    # tags' names and no record: the mind graph asks for every readable post
    # at once (`PostGraph::Listings`), from rows it has already loaded. THE
    # ONE PLACE the per-post test is written: `lists?` below is this, so the
    # listing, a post's address and the graph cannot come to disagree about
    # which page lists which post. Still in lockstep with `listed_posts`.
    def self.matches?(settings, content_type:, tag_names:)
      return false if ContentTypes.find(content_type).nil?
      return false if settings.content_type.present? && settings.content_type.to_s != content_type.to_s

      tag = settings.tag.to_s.strip
      tag.blank? || tag_names.any? { |name| name.to_s.downcase == tag.downcase }
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
      matches?(settings, content_type: post.content_type, tag_names: post.tags.map(&:name))
    end
  end
end
