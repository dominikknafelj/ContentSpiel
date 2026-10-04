module Admin
  # `Admin::PermissionMatrixComponent` (round 3 Task 10): the eleven rows with
  # their scope chips and "Edit scope", and the toggle cards. Rendered with no
  # signed-in actor, which the checker trusts like the console, so the branch
  # tree lists every page.
  class PermissionMatrixComponentPreview < ViewComponent::Preview
    # A new group: nothing ticked, every "Edit scope" held back.
    def empty
      render Admin::PermissionMatrixComponent.new(grants: [])
    end

    # An author-like group: own blog posts, one page branch, a mixed row open.
    def scoped
      about = PreviewFixtures.page(title: "About")
      about.children.create!(page_type: :standard, title: "Team #{SecureRandom.hex(4)}", published_at: Time.current)
      render Admin::PermissionMatrixComponent.new(grants: [
        { permission: "posts.read", scope: {} },
        { permission: "posts.edit", scope: { "content_types" => [ "blog", "now_update" ], "own" => true } },
        { permission: "pages.edit", scope: { "page_ids" => [ about.id ] } },
        { permission: "tags.manage", scope: {} }
      ], open_keys: [ "pages.edit" ])
    end

    # Review Focus 3: a grant scoped to a retired content type (a warn chip with
    # Remove, carried) and one whose only branch root was deleted (unticked, with
    # a note).
    def stale
      group = AccessControl::Group.create!(name: "Stale #{SecureRandom.hex(4)}")
      group.grants.create!(permission: "posts.edit", scope: { "content_types" => %w[blog retired_type] })
      group.grants.create!(permission: "pages.edit", scope: { "page_ids" => [ 0 ] })
      live = AccessControl::LiveGrants.new(group.grants.to_a)

      render Admin::PermissionMatrixComponent.new(grants: live.carried_attributes, stale: live, open_keys: [ "posts.edit" ])
    end
  end
end
