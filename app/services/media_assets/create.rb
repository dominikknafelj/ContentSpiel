module MediaAssets
  # The rich-text editor's upload endpoint's original service name, kept as
  # a plain alias of `Media::Upload` (media library Task 4) so its one caller
  # (`Admin::MediaAssetsController`) and its own tests keep working until
  # Task 6 finalises `Media::Upload` and deletes this file. A subclass, not
  # a second implementation: there is exactly one upload path, and the
  # service contract test reads `#call` from `Media::Upload`'s own source.
  class Create < Media::Upload
  end
end
