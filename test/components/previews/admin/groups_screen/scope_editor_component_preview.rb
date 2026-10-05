module Admin
  module GroupsScreen
    # `Admin::GroupsScreen::ScopeEditorComponent`, the scope controls a
    # permission row opens in place. Rendered open and alone, so the states can
    # be looked at without the row around them (Lookbook's layout has no
    # `admin--permission-matrix`, so Remove and Done do nothing here):
    # - posts: content types and "Own only", with a removed content type as its
    #   warn chip;
    # - pages, three levels deep: the chosen page ticked, everything under it a
    #   greyed tick, every ancestor a dash ("contains a chosen page");
    # - a root that is chosen AND under another chosen root (a stored state the
    #   editor never writes itself): its box is disabled as included, and a
    #   hidden input carries it;
    # - a stored root that is in the trash: no place in the tree, carried as "A
    #   page you can't open (kept)" with the warning under the tree.
    class ScopeEditorComponentPreview < ViewComponent::Preview
      def posts_with_a_removed_type
        render editor("posts.edit", scope: { "content_types" => %w[blog retired_type], "own" => true })
      end

      def pages_partial_over_several_levels
        _about, team, = family
        render editor("pages.edit", scope: { "page_ids" => [ team.id ] }, tree: tree)
      end

      def pages_chosen_and_implied
        about, team, = family
        render editor("pages.edit", scope: { "page_ids" => [ about.id, team.id ] }, tree: tree)
      end

      def pages_with_a_trashed_root
        about, team, member = family
        [ team, member ].each { |page| page.update_columns(trashed_at: 1.hour.ago, trash_root_id: team.id) }
        render editor("pages.edit", scope: { "page_ids" => [ about.id, team.id ] }, tree: tree)
      end

      private

      def editor(key, scope:, tree: nil, **options)
        Admin::GroupsScreen::ScopeEditorComponent.new(permission: AccessControl::Permissions.fetch(key), scope: scope, tree: tree,
          id: "scope-editor-preview", open: true, **options)
      end

      # Home > About > Team > Member.
      def family
        about = PreviewFixtures.page(title: "About")
        team = about.children.create!(page_type: :standard, title: "Team #{SecureRandom.hex(4)}", published_at: Time.current)
        member = team.children.create!(page_type: :standard, title: "Member #{SecureRandom.hex(4)}", published_at: Time.current)
        [ about, team, member ]
      end

      # As the trusted nil actor a preview runs as: every kept page, readable.
      def tree = Admin::GroupsScreen::BranchTree.for(nil, locale: "en")
    end
  end
end
