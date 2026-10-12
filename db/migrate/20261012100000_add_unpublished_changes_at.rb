# When the rows of a published or scheduled page or post last moved on from
# what is published (drafts spec §4.4): set by a content write, cleared when a
# copy is taken or the changes are discarded. NULL: nothing is waiting. A
# plain column on purpose: it is read on every list, compared with nothing,
# and a record that is a draft carries whatever it kept (a reader asks
# `Publishing::State`, which ignores it).
class AddUnpublishedChangesAt < ActiveRecord::Migration[8.1]
  def change
    add_column :pages, :unpublished_changes_at, :datetime
    add_column :posts, :unpublished_changes_at, :datetime
  end
end
