# Where in the library a listing looks (docs/reference/media.md, the places):
# every kept image (All media), the images in no folder (Not in a folder), or
# the images directly in one folder, never those of its subfolders. One
# parameter, `folder`, chooses it: absent or `all`, `none`, or a folder's id.
class Media::Place
  attr_reader :folder

  # `folder` is a `Media::Folder`'s id for a folder's place, nil for the other
  # two, which `kind` tells apart.
  def initialize(kind, folder = nil)
    @kind = kind
    @folder = folder
    freeze
  end

  ALL = new(:all)
  NONE = new(:none)

  # The place `raw` names, or nil when it names none: a folder id the tree
  # does not hold, a string that is no whole number, anything but a String
  # (`?folder[]=5`). An absent or blank `folder` is All media, as is `all`.
  def self.parse(raw, tree:)
    return ALL if raw.nil? || raw == "" || raw == "all"
    return NONE if raw == "none"
    return nil unless raw.is_a?(String) && raw.match?(/\A\d{1,18}\z/)

    id = raw.to_i
    tree.find(id) ? new(:folder, id) : nil
  end

  def all? = @kind == :all

  def none? = @kind == :none

  # "all", "none" or the folder's id, as `folder=` carries it.
  def to_param = folder ? folder.to_s : @kind.to_s

  # The place's own images of a `Media::Asset` relation.
  def narrow(scope)
    return scope if all?

    scope.where(folder_id: folder)
  end

  # What a tab that shows this place holds to learn, when the library
  # changed elsewhere, whether what it shows changed (the card's D13): an MD5
  # over the place's kept image ids in order and the names of the folders on
  # its path, so a move in or out, a trash, or a rename above it changes it,
  # and a move between two other places does not. One aggregate statement;
  # `tree` is the folder tree the path is read from.
  def digest(tree)
    assets = Media::Asset.arel_table
    names = folder ? tree.path(folder).map(&:name).to_json : ""
    joined = SqlNodes.ordered_join(assets[:id], ",", order: assets[:id])
    narrow(Media::Asset.kept).pick(SqlNodes.function("md5", SqlNodes.function("CONCAT", joined, "|", names)))
  end

  def ==(other) = other.is_a?(Media::Place) && other.to_param == to_param

  alias_method :eql?, :==

  def hash = to_param.hash
end
