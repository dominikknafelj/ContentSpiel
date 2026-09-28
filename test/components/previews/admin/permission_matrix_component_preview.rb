module Admin
  # `Admin::PermissionMatrixComponent` (access-control design spec §5): the
  # group editor's permission checkboxes by area, with scope controls under
  # each ticked scoped permission. Rendered with no signed-in actor, which
  # the checker trusts like the console, so the branch picker lists every
  # page.
  class PermissionMatrixComponentPreview < ViewComponent::Preview
    # A new group: nothing ticked, every scope control hidden.
    def empty
      render Admin::PermissionMatrixComponent.new(grants: [])
    end

    # An author-like group: own blog posts, one page branch.
    def scoped
      branch = PreviewFixtures.page(title: "About")
      render Admin::PermissionMatrixComponent.new(grants: [
        { permission: "posts.read", scope: {} },
        { permission: "posts.edit", scope: { "content_types" => [ "blog" ], "own" => true } },
        { permission: "pages.edit", scope: { "page_ids" => [ branch.id ] } }
      ])
    end

    # Review Focus 3: a grant scoped to a retired content type and one
    # whose only branch root was deleted -- shown as removed, the dead one
    # unticked.
    def stale
      group = AccessControl::Group.create!(name: "Stale #{SecureRandom.hex(4)}")
      group.grants.create!(permission: "posts.edit", scope: { "content_types" => %w[blog retired_type] })
      group.grants.create!(permission: "pages.edit", scope: { "page_ids" => [ 0 ] })
      live = AccessControl::LiveGrants.new(group.grants.to_a)

      render Admin::PermissionMatrixComponent.new(grants: live.attributes, stale: live)
    end
  end
end
