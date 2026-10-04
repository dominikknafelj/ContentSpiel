require "test_helper"

# `Admin::RecordHeaderComponent`'s own "Move to trash" gate (Task 10, trash
# spec §4.1): a page with kept subpages is no longer refused -- its whole
# branch moves along with it -- so only the homepage still disables the
# button, and the confirm dialog names how many subpages are coming too.
class Admin::RecordHeaderComponentTest < ViewComponent::TestCase
  include ContentHelper

  test "a page with kept children offers Move to trash, enabled, naming the subpage count" do
    parent = create_page(title: "Section")
    create_page(title: "Child one", parent: parent)
    create_page(title: "Child two", parent: parent)

    render_inline Admin::RecordHeaderComponent.new(page: parent.reload, locale: "en")

    assert_selector "button", text: "Move to trash"
    assert_no_selector "button[disabled]", text: "Move to trash"
    assert_text "This also moves 2 subpages to the trash."
  end

  test "a leaf page's dialog body has no subpage sentence" do
    leaf = create_page(title: "Leaf")

    render_inline Admin::RecordHeaderComponent.new(page: leaf, locale: "en")

    assert_selector "button", text: "Move to trash"
    assert_no_text "subpage"
  end

  test "the homepage's Move to trash stays disabled with the reason, even with kept children" do
    create_page(title: "Child of home", parent: root_page)

    render_inline Admin::RecordHeaderComponent.new(page: root_page.reload, locale: "en")

    assert_selector "button[disabled][title=\"The homepage can't be deleted\"]", text: "Move to trash"
    assert_no_selector "dialog"
  end

  # "View on site" used to be the absolute URL on the configured public
  # host -- on a local checkout (no PUBLIC_HOST) that was the placeholder
  # www.example.com, a dead link. The site is served by this same app, so
  # the link is the path; only "Copy" needs an absolute address, and it
  # falls back to the request's own origin when no host is configured.
  test "View on site is a same-origin path, and Copy uses the request's origin when no public host is configured" do
    without_public_host do
      page = create_page(title: "About", published: true)

      render_inline Admin::RecordHeaderComponent.new(page: page.reload, locale: "en")

      assert_selector "a[href='/about']", text: "View on site"
      assert_selector "button[data-admin--clipboard-url-value='http://test.host/about']", text: "Copy"
      assert_no_text "example.com"
    end
  end

  test "Copy uses the configured public host when there is one; View on site stays same-origin" do
    without_public_host do
      ENV["PUBLIC_HOST"] = "https://www.my-site.test"
      page = create_page(title: "About", published: true)

      render_inline Admin::RecordHeaderComponent.new(page: page.reload, locale: "en")

      assert_selector "a[href='/about']", text: "View on site"
      assert_selector "button[data-admin--clipboard-url-value='https://www.my-site.test/about']"
    end
  end

  private

  def without_public_host
    saved = ENV.to_h.slice("PUBLIC_HOST", "SITEMAP_HOST")
    ENV.delete("PUBLIC_HOST")
    ENV.delete("SITEMAP_HOST")
    yield
  ensure
    ENV.delete("PUBLIC_HOST")
    ENV.delete("SITEMAP_HOST")
    saved.each { |key, value| ENV[key] = value }
  end
end
