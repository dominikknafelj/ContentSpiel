module Admin
  module GroupsScreen
    # `Admin::GroupsScreen::PermissionRowComponent`: an unticked row, a mixed
    # scope with a removed type, and a pages row with its tri-state tree open.
    class PermissionRowComponentPreview < ViewComponent::Preview
      def unticked
        render Admin::GroupsScreen::PermissionRowComponent.new(permission: AccessControl::Permissions.fetch("posts.delete"))
      end

      def mixed_scope_with_a_removed_type
        render Admin::GroupsScreen::PermissionRowComponent.new(permission: AccessControl::Permissions.fetch("posts.edit"),
          scope: { "content_types" => %w[blog now_update retired_type], "own" => true }, open: true)
      end

      def pages_tree
        home = PreviewFixtures.page(title: "Home")
        about = home.children.create!(page_type: :standard, title: "About #{SecureRandom.hex(4)}", published_at: Time.current)
        about.children.create!(page_type: :standard, title: "Team #{SecureRandom.hex(4)}", published_at: Time.current)
        tree = Admin::GroupsScreen::BranchTree.for(nil, locale: "en")
        render Admin::GroupsScreen::PermissionRowComponent.new(permission: AccessControl::Permissions.fetch("pages.edit"),
          scope: { "page_ids" => [ about.id ] }, tree: tree, open: true)
      end
    end
  end
end
