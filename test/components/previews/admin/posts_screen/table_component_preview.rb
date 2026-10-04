module Admin
  module PostsScreen
    # The posts list's table with a few sample rows (needs a post or two in
    # the development database).
    class TableComponentPreview < ViewComponent::Preview
      def default
        posts = Post.kept.order(updated_at: :desc).limit(5).to_a
        states = posts.index_with { { "de" => :complete, "es" => :outdated } }
        render Admin::PostsScreen::TableComponent.new(posts:, paths: {}, translation_states: states)
      end
    end
  end
end
