# The `Media::` namespace (media library sub-project, docs/roadmap.md):
# `Media::Asset` today (Task 1 renamed it from the bare `MediaAsset`), with
# `Media::Usage` and the upload/manage services (Tasks 2-6) to follow inside
# the same module. Zeitwerk needs this file to exist -- an empty reopenable
# module, not a class -- so it can autoload `Media::Asset` from `media/
# asset.rb` without first finding a top-level `Media` constant defined some
# other way.
module Media
end
