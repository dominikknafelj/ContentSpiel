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

  def ==(other) = other.is_a?(Media::Place) && other.to_param == to_param

  alias_method :eql?, :==

  def hash = to_param.hash
end
