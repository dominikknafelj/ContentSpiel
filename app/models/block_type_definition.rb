# A registered block type (spec §3.1 example: `post_list`, `image`, ...):
# adds the one thing a block needs beyond the shared `TypeDefinition` --
# which ViewComponent renders it (`pages/show.html.erb`'s block dispatch,
# sub-project 5).
class BlockTypeDefinition < TypeDefinition
  # Reader/writer, like `label` -- `component` set once during registration,
  # read by the dispatch loop with no arguments.
  def component(klass = nil)
    klass.nil? ? @component : (@component = klass)
  end
end
