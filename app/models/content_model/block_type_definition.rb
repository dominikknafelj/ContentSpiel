# A registered block type (spec §3.1 example: `post_list`, `image`, ...):
# adds the one thing a block needs beyond the shared `ContentModel::Definition`
# -- which ViewComponent renders it (`pages/show.html.erb`'s block dispatch,
# sub-project 5).
module ContentModel
  class BlockTypeDefinition < Definition
    dsl_attribute :component
  end
end
