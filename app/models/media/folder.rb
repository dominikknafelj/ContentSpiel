# A folder of the media library (docs/reference/media.md): a named place an
# image sits in, or in none. Folders nest at most MAX_DEPTH levels and a site
# holds at most MAX_FOLDERS; those two limits, and the one name per parent in
# any case, are decided by the services under the table lock, not here --
# this class holds only what one row can say of itself. A folder is never
# drawn on the site, so no write of one touches a published copy.
class Media::Folder < ApplicationRecord
  # Explicit: Zeitwerk's demodulized default would be `folders`.
  self.table_name = "media_folders"

  MAX_DEPTH = 4
  MAX_FOLDERS = 1000
  NAME_LENGTH = 80

  belongs_to :parent, class_name: "Media::Folder", optional: true
  belongs_to :created_by, class_name: "User", optional: true
  has_many :children, class_name: "Media::Folder", foreign_key: :parent_id, inverse_of: :parent
  # `dependent:` stays unset: the foreign key nullifies an image's folder, and
  # the services move images out before a delete so none is left to rely on it.
  has_many :assets, class_name: "Media::Asset", foreign_key: :folder_id, inverse_of: :folder

  # A name is stripped before it is judged, so "  " is blank and a trailing
  # space never makes a second "Trips".
  normalizes :name, with: ->(name) { name.strip }

  validates :name, presence: { message: "Give the folder a name." }
  validates :name, length: { maximum: NAME_LENGTH, message: "Use at most #{NAME_LENGTH} characters." }
  validate :name_holds_no_control_character

  # THE TREE'S LOCK, the first statement of every write to the folder tree
  # (`Media::SaveFolder`, `Media::DeleteFolder`): the depth, the count and the
  # one-name-per-parent rules are judged from a read of the whole tree, which a
  # second writer would change under the first. SHARE ROW EXCLUSIVE lets plain
  # reads and image writes go on and excludes every other tree writer until the
  # transaction ends. Call it inside a transaction, before `FolderTree.load`.
  def self.lock_tree!
    # sql: neither Active Record nor Arel has a table lock; a constant statement
    connection.execute("LOCK TABLE media_folders IN SHARE ROW EXCLUSIVE MODE") # version: none (a folder is never drawn on the site)
    nil
  end

  private

  def name_holds_no_control_character
    errors.add(:name, "Use no control characters in a name.") if name&.match?(/\p{Cc}/)
  end
end
