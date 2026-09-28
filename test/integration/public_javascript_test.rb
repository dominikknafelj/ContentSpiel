require "test_helper"

# Task 7 fix round 1: the public site shares the importmap entrypoint with
# CS Studio, but must not download the admin-only editor stack. The
# Tiptap/ProseMirror pins are `preload: false` (no `<link rel=modulepreload>`
# for them) and `controllers/admin/*` is lazy-loaded
# (app/javascript/controllers/index.js), so nothing on a public page imports
# them either. They stay *in* the import map -- that's how CS Studio's lazy
# import resolves them.
class PublicJavascriptTest < ActionDispatch::IntegrationTest
  test "a public page doesn't modulepreload the editor stack" do
    create_page(title: "About")

    get "/"

    assert_response :success
    preloads = css_select("link[rel=modulepreload]").map { |link| link["href"] }
    assert preloads.any?, "expected the application's own modules to be preloaded"
    %w[@tiptap prosemirror linkifyjs sortablejs d3-force].each do |name|
      assert preloads.none? { |href| href.include?(name) }, "#{name} is modulepreloaded on a public page: #{preloads.grep(/#{Regexp.escape(name)}/).inspect}"
    end

    importmap = JSON.parse(css_select("script[type=importmap]").first.text)["imports"]
    assert importmap.key?("@tiptap/core"), "the editor must stay resolvable for CS Studio's lazy import"
  end
end
