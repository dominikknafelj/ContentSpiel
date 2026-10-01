module Admin
  # The post editor's own tag input (cs-studio spec §5.2): one free-text
  # field an editor types comma-separated tag names into (existing or new),
  # not `Admin::Fields::TagField`'s single-value `:tag` schema field (see
  # that class's own comment on the distinction) -- new tags are only ever
  # created on save, through `Posts::Save`'s `tag_names:`
  # (`Admin::PostsController#update` splits this field's one submitted
  # string back into an Array first). Autocomplete for the tag currently
  # being typed -- not the whole field at once, which a bare `<input
  # list=...>` only ever matches against -- is `admin--tag-input`'s job; see
  # that controller's own comment for how it rebuilds the shared `<datalist>`
  # per keystroke to make that work.
  class TagInputComponent < AdminComponent
    # A site with thousands of tags would otherwise hand every single one
    # of them to the browser on every post editor load, just so `admin--
    # tag-input` can filter its own `<datalist>` down to the handful that
    # actually match whatever's currently being typed (cs-studio final-fixes
    # round, finding 13) -- capped at the tags actually worth suggesting
    # first: the ones already used the most, since those are also the ones
    # an editor typing a tag name is likeliest to be reaching for again. A
    # tag outside this cap is never unreachable -- it still autocompletes
    # perfectly well once its own first few characters narrow the count down
    # -- this only trims the *unfiltered* list a fresh page load starts from.
    MAX_SUGGESTED_TAGS = 200

    def initialize(value:, name: "post[tag_names]", id: "post-tag_names", errors: [])
      @value = value
      @name = name
      @id = id
      @errors = errors
    end

    def datalist_id = "#{id}-tags"

    # `left_joins(:posts)`, not `tag.posts.count` per row -- the same N+1
    # `Admin::TagsController#index`'s own comment already rules out for its
    # list, just ranking instead of merely counting. Ties (equally-used
    # tags, including every tag with zero posts at all) fall back to
    # alphabetical, so the cap's own cutoff is deterministic rather than
    # depending on whatever order Postgres happens to return equal counts
    # in. Kept posts only, the same count `Admin::TagsController#index`
    # shows: a trashed post doesn't make its tags likelier to be wanted.
    def tag_names
      Tag.left_joins(:posts)
        .group(:id)
        .order(Arel.sql("COUNT(posts.id) FILTER (WHERE posts.trashed_at IS NULL) DESC"), Arel.sql("LOWER(tags.name) ASC"))
        .limit(MAX_SUGGESTED_TAGS)
        .pluck(:name)
    end

    def errors_id = "#{id}-errors"

    private

    attr_reader :value, :name, :id, :errors
  end
end
