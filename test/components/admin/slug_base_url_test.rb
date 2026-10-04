require "test_helper"
require Rails.root.join("test/components/previews/preview_fixtures")

# Design pass bug 1, the SOURCE fix: the root page's own path is "/", so a
# child of the root (or a listing page that IS the root) used to hand the slug
# field a base ending in a slash, and the prefix read "//about" (and
# "/de//about" in a non-default language).
class Admin::SlugBaseUrlTest < ViewComponent::TestCase
  setup do
    site_settings(:default).update!(locales: [ { "code" => "en" }, { "code" => "de" } ])
    @root = PreviewFixtures.root_page
  end

  test "a child of the root page: the page form's prefix has no doubled slash, in either language" do
    child = PreviewFixtures.page(title: "Child")
    %w[en de].each do |locale|
      component = Admin::PageSettingsFormComponent.new(page: child, locale: locale)
      # The source, not just the defensive `SlugColumnComponent#prefix` on top of it.
      assert_no_match %r{/\z}, component.send(:slug_base_url) unless component.send(:slug_base_url).empty?
      as_owner { render_inline component }
      assert_no_text "//"
      assert_selector ".admin-prefix-input span.bg-sunken", text: %r{\A#{locale == "de" ? "/de" : ""}/\z}
    end
  end

  test "a page below another page keeps exactly one slash between segments" do
    parent = PreviewFixtures.page(title: "Parent")
    child = parent.children.create!(page_type: :standard, title: "Grandchild #{SecureRandom.hex(4)}", published_at: Time.current)
    as_owner { render_inline Admin::PageSettingsFormComponent.new(page: child, locale: "de") }
    assert_no_text "//"
    assert_selector ".admin-prefix-input span.bg-sunken", text: %r{\A/de/.+/\z}
  end

  test "a post listed on the root page: the post form's prefix has no doubled slash, in either language" do
    @root.content_blocks.create!(block_type: :post_list, position: 0, settings: { "content_type" => "blog" })
    post = PreviewFixtures.post(title: "Listed")
    %w[en de].each do |locale|
      component = Admin::PostFormComponent.new(post: post, locale: locale)
      assert_no_match %r{/\z}, component.send(:slug_base_url)
      as_owner { render_inline component }
      assert_no_text "//"
    end
  end
end
