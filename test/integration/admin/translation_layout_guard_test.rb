require "test_helper"

# `.admin-translation-pair` only becomes two columns inside an
# `.admin-translation-form` (the container its `@container` rules query), so a
# screen that renders originals without one silently stacks forever. Every
# screen that can show an original on a translation tab is rendered here.
class Admin::TranslationLayoutGuardTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    with_locales(%w[en de], default: "en")
    sign_in_as(users(:one))
  end

  def assert_pairs_inside_containers(path)
    get path, params: { locale: "de" }
    assert_response :success
    assert_select ".admin-translation-pair", minimum: 1
    assert_select ".admin-translation-pair" do |pairs|
      pairs.each do |pair|
        assert pair.ancestors.any? { |node| node.respond_to?(:[]) && node["class"].to_s.split.include?("admin-translation-form") },
          "a .admin-translation-pair on #{path} has no .admin-translation-form ancestor"
      end
    end
  end

  test "the page editor and its block cards" do
    page = create_page(title: "About")
    ContentBlocks::Save.call(page.content_blocks.new, attributes: { block_type: "rich_text" }, translations: { "en" => { body: rich_doc("Hello") } })
    assert_pairs_inside_containers "/cs-studio/pages/#{page.id}"
    assert_select ".admin-block-card .admin-translation-pair"
  end

  test "the post editor" do
    assert_pairs_inside_containers "/cs-studio/posts/#{create_post(title: "Hello").id}"
  end

  test "Settings" do
    assert_pairs_inside_containers "/cs-studio/settings"
  end

  test "the media detail" do
    asset = create_media_asset
    assert Media::Save.call(asset, translations: { "en" => { alt: "Sand dunes" } }).ok?
    assert_pairs_inside_containers "/cs-studio/media?selected=#{asset.id}"
  end
end
