# A registered block type (spec §3.1 example: `post_list`, `image`, ...):
# adds the one thing a block needs beyond the shared `ContentModel::Definition`
# -- which ViewComponent renders it (`pages/show.html.erb`'s block dispatch,
# this sub-project's Task 4).
module ContentModel
  class BlockTypeDefinition < Definition
    dsl_attribute :component

    # A container type (`:container`, sections spec §3.1) says how many columns
    # a block of it has: a callable taking the block's `settings` hash and
    # answering an Integer. It is a callable, not a number, because the count
    # is a property of each block's own layout setting, and it lives on the
    # definition so that `ContentBlock#column_count` asks the type instead of
    # anything comparing a block's type with a name.
    dsl_attribute :columns

    # The `lists_posts` capability is a promise that `BlockTypes::PostList`
    # (today's only holder of it) can actually keep: `.listed_posts`/`.lists?`
    # read `settings.content_type`/`settings.tag` unconditionally, with no
    # guard of their own, because every *built-in* caller already declares
    # both fields. A type that claims the capability without them would only
    # find that out as a `NoMethodError` the first time a listing block
    # actually renders -- checked here instead, at registration, so a
    # developer error fails loudly at boot rather than at request time.
    #
    # The same goes for `:container`: `ContentBlock#column_count` calls
    # `columns` on every container block without a guard, so a container type
    # registered without it is refused here too.
    def finalize!
      raise ArgumentError, "a container block type needs `columns`" if capability?(:container) && columns.nil?

      if capability?(:lists_posts)
        missing = %w[content_type tag] - fields.map(&:name)
        raise ArgumentError, "a lists_posts block type needs #{missing.join(' and ')} field(s)" if missing.any?
      end
    end
  end
end
