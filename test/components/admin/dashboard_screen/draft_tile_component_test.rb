require "test_helper"

# `Admin::DashboardScreen::DraftTileComponent`: one of the viewer's drafts in
# "Pick up where you left off", a tile that presses as one (its title link
# stretched over it) and ends in "Continue".
class Admin::DashboardScreen::DraftTileComponentTest < ViewComponent::TestCase
  setup { Current.actor = users(:one) }
  teardown { Current.reset }

  test "a draft tile shows its type, title, two lines of excerpt and when it was edited, and ends in Continue" do
    post = create_post(title: "Half-written", published: false)
    post.update_columns(excerpt: { Locales.default => "Where the story begins." })

    render_inline Admin::DashboardScreen::DraftTileComponent.new(record: post.reload)

    assert_selector "article.admin-draft-tile.rounded-tile.bg-surface.shadow-1.p-4" do
      assert_selector ".admin-type-dot", text: "Blog"
      assert_selector "a.admin-draft-tile__link.text-h3[href='/cs-studio/posts/#{post.id}'][data-turbo-frame=_top]", exact_text: "Half-written"
      assert_selector "p.line-clamp-2", exact_text: "Where the story begins."
      assert_text(/edited just now/)
      assert_selector "time"
      assert_selector "span.admin-row-verb", exact_text: "Continue"
      assert_selector "a", count: 1
    end
    verb_id = page.find("span.admin-row-verb")[:id]
    assert_predicate verb_id, :present?
    assert_equal verb_id, page.find("a.admin-draft-tile__link")["aria-describedby"]
    assert_includes page.find("article")[:class], "hover:shadow-2"

    draft = create_page(title: "About", published: false)
    render_inline Admin::DashboardScreen::DraftTileComponent.new(record: draft)
    assert_selector "article.admin-draft-tile" do
      assert_selector "a.admin-draft-tile__link[href='/cs-studio/pages/#{draft.id}']", exact_text: "About"
      assert_text "Page"
      assert_no_selector ".admin-type-dot"
      assert_no_selector "p.line-clamp-2"
    end

    post.update_columns(title: {}, excerpt: {})
    render_inline Admin::DashboardScreen::DraftTileComponent.new(record: post.reload)
    assert_selector "a.admin-draft-tile__link", exact_text: "(untitled)"
    assert_no_selector "p.line-clamp-2"
  end

  test "a tile's excerpt is escaped text" do
    post = create_post(title: "Sneaky", published: false)
    post.update_columns(excerpt: { Locales.default => "<script>alert(1)</script> and <b>bold</b>" })

    render_inline Admin::DashboardScreen::DraftTileComponent.new(record: post.reload)

    assert_selector "p.line-clamp-2", exact_text: "<script>alert(1)</script> and <b>bold</b>"
    assert_no_selector "article script"
    assert_no_selector "article b"
  end
end
