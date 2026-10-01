module Trash
  # The one permission rule for acting on a single trashable item (trash spec
  # §6): its ordinary delete right -- scopes included, so a branch-scoped
  # `pages.delete` only reaches that branch -- or, for an image,
  # `media.manage` / being its uploader with `media.upload` (`Media::
  # Ownership`, the same rule `Media::Destroy` used). `trash.empty` also
  # allows purging (see `Trash::Purge`), never moving or restoring.
  #
  # Returns the permission key to hand `denied`, or nil when allowed -- an
  # image reports `media.manage`, the right that isn't bounded by ownership.
  # The check itself is the block, `{ |key| authorize!(key, record) }`,
  # written out in each service's own `#call` -- the same shape as
  # `ContentBlocks::OwnerPermissions#owner_refusal`, so
  # `test/services/service_contract_test.rb` still finds `authorize!(` in
  # the service's own file.
  module ItemPermissions
    include Media::Ownership

    private

    def item_refusal(record)
      case record
      when Page then "pages.delete" unless yield("pages.delete")
      when Post then "posts.delete" unless yield("posts.delete")
      when Media::Asset then "media.manage" unless yield("media.manage") || uploader_may_manage?(record)
      else raise ArgumentError, "#{record.class} can't go to the trash"
      end
    end

    # How a refusal names the root of the branch a page went to the trash
    # with: by title only when the actor may read it -- the subpage's own
    # delete right can be scoped to a branch that doesn't reach the root,
    # and its title isn't theirs to learn ("not found, not forbidden").
    # Also the answer when the root is gone altogether.
    def branch_root_name(root)
      if root && AccessControl.allowed?(actor, "pages.read", root)
        "“#{root.title}”"
      else
        "the page it was moved to the trash with"
      end
    end
  end
end
