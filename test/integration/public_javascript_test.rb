require "test_helper"

# Final fix wave (D, P12/P14): the public site and CS Studio load separate
# import-map entry points. A public page imports `application` -- Turbo and
# the site's own controllers only -- and modulepreloads nothing of CS
# Studio's: not its controllers (`controllers/admin/*`), not the editor's
# own modules (`rich_text/*`), not Tiptap/ProseMirror, SortableJS or D3.
# CS Studio's layout imports `admin`, which registers the admin controllers
# too, and modulepreloads the editor stack (`preload: "admin"` in
# config/importmap.rb) so the editor mounts without a waterfall of imports.
# The import map itself is the same on both (it's only a lookup table);
# what differs is what each page preloads and imports.
class PublicJavascriptTest < ActionDispatch::IntegrationTest
  ADMIN_ONLY = %w[controllers/admin/ rich_text/ @tiptap prosemirror linkifyjs sortablejs d3-force].freeze

  test "a public page loads the application entry point without any admin module" do
    create_page(title: "About")

    get "/"

    assert_response :success
    preloads = modulepreloads
    assert preloads.any? { |href| href.include?("application") }, "expected the application entry point to be preloaded"
    ADMIN_ONLY.each do |name|
      assert preloads.none? { |href| href.include?(name) }, "#{name} is modulepreloaded on a public page: #{preloads.grep(/#{Regexp.escape(name)}/).inspect}"
    end
    assert_includes entry_point_script, %(import "application")
    assert_not_includes entry_point_script, %(import "admin")
  end

  test "CS Studio loads the admin entry point and preloads the editor stack" do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
    post = create_post(title: "Notes")

    get "/cs-studio/posts/#{post.id}"

    assert_response :success
    preloads = modulepreloads
    %w[admin @tiptap--core controllers/admin/rich_text_controller rich_text/schema prosemirror-model].each do |name|
      assert preloads.any? { |href| href.include?(name) }, "expected #{name} to be modulepreloaded in CS Studio: #{preloads.inspect}"
    end
    assert_includes entry_point_script, %(import "admin")
  end

  private

  def modulepreloads = css_select("link[rel=modulepreload]").map { |link| link["href"] }

  def entry_point_script = css_select("script[type=module]").map(&:text).join("\n")
end
