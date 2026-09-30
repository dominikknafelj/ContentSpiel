# What's in the trash, as the purgeable top-level items (trash spec §4.4):
# page branches by their root, then posts, then images -- images last, so
# the usages their trashed owners held are gone by the time they're tried.
#
# `Trash` is both this module and the namespace of the `Trash::` services
# (`app/services/trash/`); Zeitwerk takes this file as the namespace's
# definition and the directory as its children.
module Trash
  module_function

  # A page root is a trashed page whose `trash_root_id` is its own id: the
  # page the editor actually picked. Its branch members (same
  # `trash_root_id`) go with it through `Trash::Purge`, never on their own.
  def roots
    {
      pages: Page.trashed.where("pages.trash_root_id = pages.id").order(:trashed_at, :id),
      posts: Post.trashed.order(:trashed_at, :id),
      assets: Media::Asset.trashed.order(:trashed_at, :id)
    }
  end

  # Yields each root freshly loaded, in `roots` order. The ids are read up
  # front but each record only when its turn comes, and skipped if it's gone
  # by then: a subpage trashed on its own is a root of its own, yet an
  # earlier-tried ancestor's branch purge may already have taken it -- a
  # stale in-memory copy would otherwise be "purged" (and audited) twice.
  # Not `find_each`, which ignores the order this depends on.
  def each_root
    roots.each_value do |relation|
      relation.pluck(:id).each do |id|
        record = relation.find_by(id:)
        yield record if record
      end
    end
  end
end
