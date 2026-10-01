require "test_helper"

# The `Admin::Media` trap (`test/lib/admin_media_namespace_test.rb`), for
# the trash: an `Admin::Trash` module -- the obvious name for the Trash
# screen's components, which live under `Admin::TrashScreen` instead --
# would shadow the top-level `Trash` module (`app/models/trash.rb`,
# `app/services/trash/*`) for every bare `Trash::Move`/`Trash::Restore`
# lexically nested under `module Admin` (the Pages, Posts, Media and Trash
# controllers all have one).
module Admin
  module TrashNamespaceProbe
    def self.resolve_trash_move
      Trash::Move
    end
  end
end

class AdminTrashNamespaceTest < ActiveSupport::TestCase
  setup { Rails.application.eager_load! }

  test "nothing defines Admin::Trash" do
    assert_not Admin.const_defined?(:Trash, false),
      "Admin::Trash exists, which would shadow the top-level Trash module for every bare Trash:: " \
        "reference lexically nested under module Admin -- see Admin::TrashScreen's own comment"
  end

  test "a bare Trash:: reference lexically nested under Admin still resolves to the top-level services" do
    assert_equal Trash::Move, Admin::TrashNamespaceProbe.resolve_trash_move
  end
end
