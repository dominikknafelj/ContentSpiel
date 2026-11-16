require "test_helper"

# The History screen's heading row: the editor's crumbs ending in History,
# the title with its state, and Back to editor.
class Admin::HistoryScreen::HeadComponentTest < ViewComponent::TestCase
  include ContentHelper

  test "a page's crumbs lead through its ancestors to its editor, then History; its state is the header's" do
    parent = create_page(title: "Company")
    pricing = create_page(title: "Pricing", parent: parent)
    assert Pages::Save.call(pricing, translations: { "en" => { title: "Prices" } }).ok?

    as(users(:one)) { render_inline Admin::HistoryScreen::HeadComponent.new(record: pricing.reload, locale: "en") }

    assert_equal [ "Pages", "Home", "Company", "Prices", "History" ], page.all("nav[aria-label=Breadcrumb] a, nav[aria-label=Breadcrumb] span:not([aria-hidden])").map(&:text)
    assert_selector "nav span[aria-current=page]", text: "History"
    assert_selector "h1", text: "Prices"
    assert_selector ".admin-status-chip", text: "Live"
    assert_selector "[data-unpublished-changes]", text: "Unpublished changes"
    assert_selector "a[href='/cs-studio/pages/#{pricing.id}']", text: "Back to editor"
  end

  test "a post's crumbs are Posts and its type" do
    news = create_post(title: "News", published: false)

    as(users(:one)) { render_inline Admin::HistoryScreen::HeadComponent.new(record: news, locale: "en") }

    assert_equal [ "Posts", "Blog", "News", "History" ], page.all("nav[aria-label=Breadcrumb] a, nav[aria-label=Breadcrumb] span:not([aria-hidden])").map(&:text)
    assert_selector ".admin-status-chip", text: "Draft"
    assert_no_selector "[data-unpublished-changes]"
  end
end
