require "test_helper"

class Admin::TreeTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
    @a = create_page(title: "Alpha")
    @b = create_page(title: "Beta")
    @child = create_page(title: "Child", parent: @a)
  end

  # Fix (final-fixes round, finding 11): the tree's own bare GET answered a
  # plain browser request with a Turbo Stream body -- unusable outside a
  # frame fetch, and nothing in the app ever actually made one. Removed
  # (route and action) rather than turned into real HTML, since every real
  # navigation already gets the tree for free via `content_for :tree`.
  test "the tree's own GET route no longer exists" do
    get "/cs-studio/tree"
    assert_response :not_found
  end

  test "the pages index shows the tree with status and child counts" do
    get "/cs-studio/pages"
    assert_select "turbo-frame#tree li[data-page-id='#{@a.id}']" do
      # The tree hides Live: only a draft or scheduled page gets a chip.
      assert_select "[data-status='live']", count: 0
      assert_select "[data-child-count]", text: "1"
    end
  end

  test "moving a page reparents it and re-renders the tree" do
    patch "/cs-studio/tree", params: { page_id: @child.id, parent_id: @b.id, position: 0 }, as: :turbo_stream
    assert_response :success
    assert_equal @b, @child.reload.parent
    assert_includes response.body, %(<turbo-stream action="replace" target="tree">)
  end

  test "an invalid move re-renders the tree unchanged with an error" do
    patch "/cs-studio/tree", params: { page_id: @a.id, parent_id: @child.id, position: 0 }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_equal root_page, @a.reload.parent
    # The status partial renders this message auto-escaped like any other
    # admin text (no `raw`), so a plain apostrophe comes back as `&#39;` --
    # decode before asserting on the human-readable text.
    assert_includes CGI.unescapeHTML(response.body), "can't be moved under itself"
  end

  test "moving a page that was deleted elsewhere re-renders the current tree with an error, not a 500" do
    stale_id = @child.id
    @child.destroy!

    patch "/cs-studio/tree", params: { page_id: stale_id, parent_id: @b.id, position: 0 }, as: :turbo_stream
    assert_response :not_found
    assert_includes response.body, "no longer exists"
    assert_includes response.body, %(<turbo-stream action="replace" target="tree">)
  end

  test "moving a page onto a target that was deleted elsewhere re-renders the current tree with an error" do
    stale_parent_id = @b.id
    @b.destroy!

    patch "/cs-studio/tree", params: { page_id: @child.id, parent_id: stale_parent_id, position: 0 }, as: :turbo_stream
    assert_response :not_found
    assert_includes response.body, "no longer exists"
    assert_equal @a, @child.reload.parent
  end

  # Translation helpers spec §4 (Task 4): one marker on a page that isn't
  # complete in some target language, its tooltip naming them.
  test "the tree marks a page incomplete in some language, naming the languages" do
    with_locales(%w[en de es], default: "en")
    assert Pages::Save.call(@a, translations: { "es" => { title: "Alfa" } }).ok?
    assert Pages::Save.call(@b, translations: { "de" => { title: "Beta" }, "es" => { title: "Beta" } }).ok?

    get "/cs-studio/pages"

    assert_select "turbo-frame#tree li[data-page-id='#{@a.id}'] > div [data-translation-marker]" do |markers|
      assert_equal 1, markers.size
      assert_equal "Incomplete in Deutsch (missing)", markers.first["title"]
      assert_equal "Incomplete in Deutsch (missing)", markers.first["aria-label"]
    end
    assert_select "turbo-frame#tree li[data-page-id='#{@b.id}'] > div [data-translation-marker]", count: 0
  end

  test "the tree marker lists outdated languages too" do
    with_locales(%w[en de es], default: "en")
    assert Pages::Save.call(@b, translations: { "de" => { title: "Beta" } }).ok?
    assert Pages::Save.call(@b, translations: { "en" => { title: "Beta!" } }).ok?

    get "/cs-studio/pages"

    assert_select "turbo-frame#tree li[data-page-id='#{@b.id}'] > div [data-translation-marker][title='Incomplete in Deutsch (outdated), Español (missing)']"
  end

  test "the tree shows no marker with one language enabled" do
    with_locales(%w[en], default: "en")

    get "/cs-studio/pages"

    assert_select "turbo-frame#tree [data-translation-marker]", count: 0
  end

  test "a context-only row never shows the marker" do
    with_locales(%w[en de es], default: "en")
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "pages.edit", scope: { "page_ids" => [ @a.id ] })
    sign_out
    sign_in_as(users(:editor_branch))

    get "/cs-studio/pages/#{@child.id}"

    assert_response :success
    assert_select "turbo-frame#tree li[data-page-id='#{root_page.id}'][data-context-only] > div" do |rows|
      assert_nil rows.first.at_css("[data-translation-marker]")
    end
    assert_select "turbo-frame#tree li[data-page-id='#{@a.id}'] > div [data-translation-marker]"
  end
end
