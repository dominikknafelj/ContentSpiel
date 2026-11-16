# The numbers the Folders column and the picker's places show: kept images
# only (a trashed image is in no count, as in the segments'), from one grouped
# query. A folder's count is its direct images; `all` is every kept image and
# `none` those in no folder. A folder holding nothing is absent from `folders`.
class Media::FolderCounts
  def self.call
    per_folder = Media::Asset.kept.unscope(:includes).group(:folder_id).count

    { all: per_folder.values.sum, none: per_folder.fetch(nil, 0), folders: per_folder.except(nil) }
  end
end
