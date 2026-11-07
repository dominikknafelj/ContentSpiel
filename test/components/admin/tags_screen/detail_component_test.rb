require "test_helper"

class Admin::TagsScreen::DetailComponentTest < ViewComponent::TestCase
  setup { Current.actor = users(:one) }
  teardown { Current.reset }

  def tag = @tag ||= Tag.create!(name: "music")

  def render_detail(posts: [], count: posts.size, carriers: count)
    render_inline Admin::TagsScreen::DetailComponent.new(tag:, posts:, count:, carriers:, locale: :en)
  end

  # The classes of one element as a set, so a match is every class of a button's variant.
  def classes_of(selector) = page.find(selector)[:class].split

  test "the detail names the tag, counts its posts, lists them newest first with their state, and links Show all to the posts list filtered by it" do
    draft = create_post(title: "A draft", published: false)
    live = create_post(title: "Live one")
    render_detail(posts: [ draft, live ], count: 12)

    assert_selector "div#tag-detail-#{tag.id}[data-tag-detail-for='#{tag.id}']"
    assert_selector "h2#tag-detail-#{tag.id}-name[tabindex='-1'][data-tag-detail-heading]", text: "music"
    assert_selector "[data-tag-detail-count]", text: "12 posts"
    assert_equal [ "A draft", "Live one" ], page.all("[data-tag-detail-posts] li a").map(&:text)
    assert_selector "[data-tag-detail-post='#{draft.id}'] a[href='/cs-studio/posts/#{draft.id}'][data-turbo-frame='_top']"
    assert_selector "[data-tag-detail-post='#{draft.id}'] .admin-status-chip[data-status=draft]", text: "Draft"
    assert_no_selector "[data-tag-detail-post='#{live.id}'] .admin-status-chip"
    assert_selector "a[data-tag-detail-show-all][href='/cs-studio/posts?tag=music'][data-turbo-frame='_top']", text: "Show all 12 posts"
  end

  test "Merge into… is a secondary button and Delete tag… the danger text button, each opening its dialog with the row's facts, and nothing is primary or filled red" do
    render_detail(count: 2, carriers: 3)

    merge = page.find("button", text: "Merge into…")
    assert_empty Admin::Ui::ButtonComponent.classes(:secondary).split - merge[:class].split
    assert_equal "merge-tag-dialog", merge["data-admin--ui--dialog-id-param"]
    assert_equal tag.id.to_s, merge["data-tag-id"]
    assert_equal "Merge “music” into…", merge["data-tag-merge-title"]
    assert_equal "Its 3 posts, including ones in the trash or that you can't open, get the chosen tag and “music” is deleted. This can't be undone.", merge["data-tag-merge-text"]

    delete = page.find("button", text: "Delete tag…")
    assert_empty Admin::Ui::ButtonComponent.classes(:danger_text).split - delete[:class].split
    assert_equal "delete-tag-dialog", delete["data-admin--ui--dialog-id-param"]
    assert_equal tag.id.to_s, delete["data-tag-id"]
    assert_equal "It is removed from 3 posts, including ones in the trash or that you can't open. The posts themselves stay.", delete["data-tag-delete-text"]

    assert_no_selector ".bg-accent"
    assert_no_selector ".bg-danger"
  end

  test "Show all is drawn only when the tag has more posts than the rail lists" do
    posts = [ create_post(title: "One"), create_post(title: "Two") ]
    render_detail(posts:, count: 2)
    assert_no_selector "[data-tag-detail-show-all]"

    render_detail(posts:, count: 3)
    assert_selector "[data-tag-detail-show-all]", text: "Show all 3 posts"

    render_detail(posts: [], count: 0)
    assert_selector "[data-tag-detail-count]", text: "0 posts"
    assert_no_selector "[data-tag-detail-posts]"
    assert_no_selector "[data-tag-detail-show-all]"
  end

  test "without posts.read there is no count and no post, and the dialogs' sentences are the neutral ones" do
    render_detail(posts: [], count: nil, carriers: nil)

    assert_no_selector "[data-tag-detail-count]"
    assert_no_selector "[data-tag-detail-posts]"
    assert_no_selector "[data-tag-detail-show-all]"
    assert_no_text(/\d/)
    assert_equal "It is removed from every post that uses it. The posts themselves stay.", page.find("button", text: "Delete tag…")["data-tag-delete-text"]
    assert_equal "Its posts get the chosen tag and “music” is deleted. This can't be undone.", page.find("button", text: "Merge into…")["data-tag-merge-text"]
  end

  test "Close is the shared icon button, named Close" do
    expected = render_inline(Admin::Ui::ButtonComponent.new(label: "Close", icon: :x, variant: :tertiary, size: :small,
      data: { action: "admin--tags--detail#close", tag_detail_close: "" })).to_html

    render_detail
    close = page.find("[data-tag-detail-close]")
    assert_equal "Close", close["aria-label"]
    # Both read back through the same parser (which spells `viewBox` in lower case).
    same = ->(html) { Nokogiri::HTML::DocumentFragment.parse(html).to_html.gsub(/\s+/, " ").strip }
    assert_equal same.(expected), same.(close.native.to_html)
  end
end
