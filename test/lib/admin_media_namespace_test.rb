require "test_helper"

# Guards against the `Admin::Media` naming trap this codebase already hit
# once (media library Task 7): a real `Admin::Media` module -- which
# `Admin::MediaLibrary::GridComponent`/`DetailComponent` deliberately don't
# define, see that class's own comment -- would shadow the top-level
# `Media` module (`app/models/media/*`, `app/services/media/*`) for every
# *bare* `Media::` reference lexically nested under `module Admin`
# elsewhere in the app: Ruby's constant lookup checks a class's own lexical
# scope, `Admin` included, before it ever falls back to the top level. That
# silently broke the hero-image and image-block upload paths mid-task
# (`NameError: uninitialized constant Admin::Media::Upload`) without a
# single line of the offending code itself changing.
#
# `Admin::MediaNamespaceProbe` is defined here, by reopening `module Admin`
# with the same block-nested form every real `Admin::*` file uses (`Admin
# ::BaseController`'s own comment lists most of them) -- so its own bare
# `Media::Upload` reference resolves exactly the way theirs would, and this
# test is actually exercising the same lookup, not a different one.
module Admin
  module MediaNamespaceProbe
    def self.resolve_media_upload
      Media::Upload
    end
  end
end

class AdminMediaNamespaceTest < ActiveSupport::TestCase
  test "nothing defines Admin::Media" do
    assert_not Admin.const_defined?(:Media, false),
      "Admin::Media exists, which would shadow the top-level Media module for every bare Media:: " \
        "reference lexically nested under module Admin -- see Admin::MediaLibrary's own comment"
  end

  test "a bare Media:: reference lexically nested under Admin still resolves to the top-level library" do
    assert_equal Media::Upload, Admin::MediaNamespaceProbe.resolve_media_upload
  end
end
