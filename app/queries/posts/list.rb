module Posts
  # The posts list's reads: its rows and the counts of its segmented scope
  # control, under the filters the list's address carries. The caller hands
  # over the viewer's readable posts (`AccessControl.scope(..., "posts.read",
  # Post.all)`, which also hides the trashed): nothing here decides who may
  # see a post.
  #
  # The filters are the address's query params, String keys, and a value
  # that is not a String is no filter (a forged `tag[]=a` filters nothing):
  # - `scope` is `all|live|drafts|scheduled` (`SCOPES`), anything else is
  #   `all`. It is the list's one name for the publish state;
  # - `type` is a content type's bare registered name;
  # - `tag` is a tag's stored name, matched exactly;
  # - `translation` is `needs|outdated|complete` (`TRANSLATIONS`,
  #   `by_translation`), anything else is no filter;
  # - `q` is a title substring matched in the editing language `locale`, not
  #   in every language: an editor filtering the list they read in one
  #   language expects that language's titles to match (`TitleSearch`, which
  #   escapes the text itself).
  class List
    SCOPES = %w[all live drafts scheduled].freeze
    TRANSLATIONS = %w[needs outdated complete].freeze

    def initialize(posts, filters:, locale:)
      @posts = posts
      @filters = filters
      @locale = locale
    end

    # The scope the list is under, always one of `SCOPES`.
    def scope_name
      @scope_name ||= string("scope").presence_in(SCOPES) || "all"
    end

    # The translation state the list is filtered by, one of `TRANSLATIONS`,
    # or nil: a value the list does not know filters nothing.
    def translation_name
      @translation_name ||= string("translation").presence_in(TRANSLATIONS)
    end

    # One page of the scope's posts, the most recently changed first (`id`
    # breaks a tie, so a page boundary never repeats or skips a row).
    def rows(limit:, offset: 0)
      by_scope(filtered).order(updated_at: :desc, id: :desc).offset(offset).limit(limit).to_a
    end

    # "All 128 · Live 96 · Drafts 20 · Scheduled 12": the four numbers in one
    # statement (`COUNT ... FILTER`), over every filter but the scope, so a
    # segment says how many posts pressing it would list. One instant is
    # bound for both comparisons, so no post is counted as live and as
    # scheduled at once. The three states are the ones `Publishable`'s scopes
    # and `Publishing::State` name (no publication time a draft, a past or
    # present one live, a future one scheduled).
    def counts
      now = Time.current
      published_at = Post.arel_table[:published_at]
      all, live, drafts, scheduled = filtered.reorder(nil).pick(
        Arel.star.count,
        SqlNodes.count_where(published_at.lteq(now)),
        SqlNodes.count_where(published_at.eq(nil)),
        SqlNodes.count_where(published_at.gt(now))
      )
      { "all" => all, "live" => live, "drafts" => drafts, "scheduled" => scheduled }
    end

    private

    def string(key)
      value = @filters[key]
      value.is_a?(String) ? value : nil
    end

    # Every filter but the scope: what the counts are taken over, and what
    # `rows` narrows by the scope.
    def filtered
      @filtered ||= begin
        scope = @posts
        scope = scope.where(content_type: string("type")) if string("type").present?
        scope = by_tag(scope, string("tag")) if string("tag").present?
        scope = by_translation(scope, translation_name) if translation_name
        scope = scope.title_matching(string("q"), locale: @locale) if string("q").present?
        scope
      end
    end

    # A subquery of ids, not `scope.joins(:tags).where(tags: { name: ... })`:
    # a `where` on the `tags` table beside an `.includes(:tags)` makes Rails
    # turn the include into an `eager_load` (one LEFT OUTER JOIN), and once
    # that join is narrowed to the matching tag, `post.tags` holds only that
    # tag for the rest of the row, not every tag the post has. The subquery
    # leaves the outer relation with no `tags` reference of its own, so a
    # caller may preload tags safely (`test/integration/admin/posts_test.rb`
    # pins that no `LEFT OUTER JOIN "tags"` appears).
    def by_tag(scope, name)
      scope.where(id: Post.joins(:tags).where(tags: { name: name }).select(:id))
    end

    # `needs` (missing or outdated in any target language), `outdated`, or
    # `complete` (neither, in every target language), read from the stored
    # `translation_states` rows: a post with no row reads as complete, the
    # rule `Translations::StateIndex` applies everywhere. An EXISTS over the
    # target languages rather than `StateIndex.joins`, which narrows by one
    # language: this filter asks about the post as a whole. The states are
    # the rolled-up ones the row's chips show (`Translations::Status`: a
    # language both missing and outdated reads as missing), so "Outdated"
    # lists exactly the posts with an outdated chip, never one whose only
    # chip in that language is missing.
    def by_translation(scope, name)
      states = name == "outdated" ? %w[outdated] : %w[missing outdated]
      exists = Translations::StateIndex.exists_in_any_locale_sql(Post, states: states, locales: Translations.target_locales)
      name == "complete" ? scope.where.not(exists) : scope.where(exists)
    end

    def by_scope(scope)
      case scope_name
      when "live" then scope.published
      when "scheduled" then scope.scheduled
      when "drafts" then scope.where(published_at: nil)
      else scope
      end
    end
  end
end
