# Two settings per person for a mention (notes spec D18, D19): the chime, on
# by default; the desktop notification, OFF by default -- it puts a note's
# first line outside CS Studio (a lock screen), and a browser grants the
# permission only on the person's own click. On the user, not in the browser,
# so they follow the person across devices; the permission itself is the
# browser's.
class AddNotesSettingsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :notes_sound, :boolean, null: false, default: true
    add_column :users, :notes_desktop, :boolean, null: false, default: false
  end
end
