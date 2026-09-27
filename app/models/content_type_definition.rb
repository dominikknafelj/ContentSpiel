# A registered content type (spec §3.1 example: `blog`, `resume_entry`,
# `now_update`): adds the mind-graph colour, the two ViewComponents a `Post`
# of this type renders through (a listing row and its own detail page,
# sub-project 5) and its starter content (what `db/seeds.rb` /
# `StarterContent` creates for a fresh install).
class ContentTypeDefinition < TypeDefinition
  def color(value = nil)
    value.nil? ? @color : (@color = value)
  end

  def list_component(klass = nil)
    klass.nil? ? @list_component : (@list_component = klass)
  end

  def detail_component(klass = nil)
    klass.nil? ? @detail_component : (@detail_component = klass)
  end

  # `section:` names the page/section this type's sample post seeds into;
  # `sample:` is the attributes (including typed `fields:`) `db/seeds.rb`
  # passes to `Posts::Save`. Read back via `starter_data`, not `starter`,
  # since `starter` itself takes the keyword arguments that set it.
  def starter(section:, sample:)
    @starter_data = { section: section, sample: sample }
  end

  def starter_data = @starter_data
end
