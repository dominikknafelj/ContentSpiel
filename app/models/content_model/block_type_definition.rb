# A registered block type (spec §3.1 example: `post_list`, `image`, ...):
# adds the one thing a block needs beyond the shared `ContentModel::Definition`
# -- which ViewComponent renders it (`pages/show.html.erb`'s block dispatch,
# this sub-project's Task 4).
module ContentModel
  class BlockTypeDefinition < Definition
    dsl_attribute :component

    # The `lists_posts` capability is a promise that `BlockTypes::PostList`
    # (today's only holder of it) can actually keep: `.listed_posts`/`.lists?`
    # read `settings.content_type`/`settings.tag` unconditionally, with no
    # guard of their own, because every *built-in* caller already declares
    # both fields. A type that claims the capability without them would only
    # find that out as a `NoMethodError` the first time a listing block
    # actually renders -- checked here instead, at registration, so a
    # developer error fails loudly at boot rather than at request time.
    def finalize!
      return unless capability?(:lists_posts)

      missing = %w[content_type tag] - fields.map(&:name)
      raise ArgumentError, "a lists_posts block type needs #{missing.join(' and ')} field(s)" if missing.any?
    end
  end
end
