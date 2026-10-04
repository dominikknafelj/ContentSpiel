# A registered content type (spec §3.1 example: `blog`, `resume_entry`,
# `now_update`): adds the colour slot (`colour_index`), the two ViewComponents a `Post`
# of this type renders through (a whole listing and its own detail page,
# this sub-project's Task 4) and its starter content (what `db/seeds.rb` /
# `StarterContent` creates for a fresh install).
module ContentModel
  class ContentTypeDefinition < Definition
    dsl_attribute :list_component
    dsl_attribute :detail_component

    # The 1-based slot in CS Studio's six-hue content-type palette
    # (`Admin::ContentTypeDotComponent`; 7-12 are the same hues as rings, 13+
    # cycle). A plain accessor, not a `dsl_attribute`: it is assigned
    # (`type.colour_index = 4`), and `Registry#register` fills in a default
    # when a type states none.
    attr_accessor :colour_index

    def finalize!
      return if colour_index.nil?
      raise ArgumentError, "colour_index must be a positive integer" unless colour_index.is_a?(Integer) && colour_index >= 1
    end

    # `section:` names the page/section this type's sample post seeds into;
    # `sample:` is the attributes (including typed `fields:`) `db/seeds.rb`
    # passes to `Posts::Save`; its `body:` is Markdown (tiptap spec §3.4),
    # which `StarterContent` converts to the JSON document a post stores --
    # a plugin's starter sample stays readable prose, not Tiptap JSON. Read back via `starter_data`, not `starter`,
    # since `starter` itself takes the keyword arguments that set it --
    # it isn't a `dsl_attribute` get/set pair.
    def starter(section:, sample:)
      @starter_data = { section: section, sample: sample }
    end

    def starter_data = @starter_data
  end
end
