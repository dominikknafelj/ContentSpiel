# The reads of CS Studio's page tree: the whole tree's rows, and one page's
# slice for a row drawn alone. A component calls them by name and builds no
# query of its own.
module PageTree
  module_function

  # The columns a row of the tree reads: its title, its order and its parent,
  # its state mark (`Publishing::State`), the branch preload
  # (`AccessControl.preload_branches`) and the row markers' loaders. Nothing
  # else is loaded, so a row that starts reading another column raises
  # `ActiveModel::MissingAttributeError` in the tree's tests until it is
  # named here.
  COLUMNS = %w[id parent_id position title published_at unpublished_changes_at].freeze

  # What are the tree's rows? The kept pages among `ids` (the viewer's
  # readable and context-only pages), with only `COLUMNS`, in the tree's
  # order (`ORDER BY position, id`, which is `TreeOrder`'s), so each parent's
  # children come grouped as they are drawn. A trashed page is left out
  # whatever the ids say.
  def rows(ids) = Page.kept.where(id: ids.to_a).select(*COLUMNS).order(:position, :id)

  # What is `page`'s row now? Its `COLUMNS`, read afresh, for a row drawn
  # alone after a save: the unpublished-changes mark is written beside the
  # save by a statement of its own (`Publishing`), so the record the request
  # holds does not carry it. Nil for a page gone to the trash.
  def row(page) = Page.kept.select(*COLUMNS).find_by(id: page.id)

  # How many children of `page` may `actor` read? Through the read scope, so
  # kept ones only. Read scopes are whole branches, so every child of a
  # readable page is readable, and this is the count the whole tree draws.
  def readable_child_count(page, actor:)
    AccessControl.scope(actor, "pages.read", Page.where(parent_id: page.id)).count
  end

  # Is `page`'s parent one `actor` can't read, that is, a context-only page
  # above the branch they may read? False for the homepage, which has none.
  def parent_context_only?(page, actor:)
    page.parent_id.present? && !AccessControl.scope(actor, "pages.read", Page.where(id: page.parent_id)).exists?
  end
end
