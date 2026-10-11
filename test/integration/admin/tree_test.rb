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
    get "/cs-studio/pages/#{@b.id}"
    assert_select "turbo-frame#tree li[data-page-id='#{@a.id}']" do
      # The tree hides Live: only a draft or scheduled page gets a chip.
      assert_select "[data-status='live']", count: 0
      assert_select "[data-child-count]", text: "1"
      assert_select "[data-child-count][role=img][aria-label='1 subpage']"
    end
  end

  # Handoff §10 C34.
  test "/pages opens Home's editor for someone who can open it" do
    get "/cs-studio/pages"
    assert_redirected_to "/cs-studio/pages/#{root_page.id}"
    assert_response :see_other
  end

  test "/pages keeps the editing language when it redirects" do
    with_locales(%w[en de], default: "en")
    get "/cs-studio/pages", params: { locale: "de" }
    assert_redirected_to "/cs-studio/pages/#{root_page.id}?locale=de"
  end

  test "moving a page reparents it and re-renders the tree" do
    patch "/cs-studio/tree", params: { page_id: @child.id, parent_id: @b.id, position: 0 }, as: :turbo_stream
    assert_response :success
    assert_equal @b, @child.reload.parent
    assert_includes response.body, %(<turbo-stream action="replace" target="tree">)
  end

  # Final fix wave 1 (reviews A I1 / B I1): `Pages::Move` saves the moved
  # page, so its `updated_at` moves -- and the page settings form of that same
  # page, open next to the tree, used to hold that as its autosave base: its
  # next save was refused as "Changed elsewhere" against the editor's own
  # move. The tree then forwarded the form's new base. Since live editing's
  # final review (I1) the form's base is `settings_changed_at` and a move does
  # not move it at all, so the form's own base is still good after the move,
  # and after its Undo.
  test "moving the open page leaves its settings form's base where it was, so its next save isn't stale" do
    base = @child.reload.settings_changed_at
    travel 1.minute
    patch "/cs-studio/tree", params: { page_id: @child.id, parent_id: @b.id, position: 0 }, as: :turbo_stream
    assert_response :success
    assert_equal base, @child.reload.settings_changed_at

    patch "/cs-studio/pages/#{@child.id}", params: { page: { subtitle: "Typed after my own move" }, base_updated_at: base.iso8601(6) }, as: :turbo_stream
    assert_response :success
    assert_equal "Typed after my own move", @child.reload.subtitle
    base = @child.settings_changed_at

    # The Undo is the same request, and moves as little.
    travel 1.minute
    patch "/cs-studio/tree", params: { page_id: @child.id, parent_id: @a.id, position: 0, undo: 1 }, as: :turbo_stream
    assert_response :success
    assert_equal base, @child.reload.settings_changed_at
  end

  # Final review I1. Someone holds the page's settings form (they are typing a
  # title) while a colleague drags that page in the tree, which stands beside
  # every page editor. A move changes nothing that form can edit, so it does
  # not move the form's base (`Page::SETTINGS_BASE_IGNORES`) and the holder's
  # next save is saved. It was a final 409 "Changed elsewhere" until a reload.
  test "a settings form held while a colleague moves that page in the tree saves afterwards" do
    base = @child.reload.settings_changed_at.iso8601(6)
    patch "/cs-studio/pages/#{@child.id}", params: { page: { subtitle: "Typing" }, base_updated_at: base },
      headers: { "X-Notes-Tab" => "tab-aaaaaaaa" }, as: :turbo_stream
    assert_response :success
    base = @child.reload.settings_changed_at.iso8601(6)
    assert Editing::Reservation.holder_of(@child), "the settings form is not held"

    travel 1.minute do
      as(users(:two), channel: :admin) { assert Pages::Move.call(@child, parent: @b, position: 0).ok? }
      assert_equal @b, @child.reload.parent

      patch "/cs-studio/pages/#{@child.id}", params: { page: { subtitle: "Typed after their move" }, base_updated_at: base },
        headers: { "X-Notes-Tab" => "tab-aaaaaaaa" }, as: :turbo_stream
      assert_response :success
      assert_equal "Typed after their move", @child.reload.subtitle
    end
  end

  test "a settings form is still refused when a colleague changed the settings, moved in the tree since or not" do
    base = @child.reload.settings_changed_at.iso8601(6)

    travel 1.minute do
      as(users(:two), channel: :admin) do
        assert Pages::Save.call(@child, translations: { "en" => { subtitle: "Theirs" } }).ok?
        assert Pages::Move.call(@child, parent: @b, position: 0).ok?
      end

      patch "/cs-studio/pages/#{@child.id}", params: { page: { subtitle: "Mine" }, base_updated_at: base }, as: :turbo_stream
      assert_response :conflict
      assert_equal "Theirs", @child.reload.subtitle
    end
  end

  # The forwarding of the page base the tree had (`X-Page-Base-Updated-At` in,
  # the hidden field's stream out) went with I1: a move no longer moves the base.
  test "a move answers no base of the page settings form, whatever a client sends" do
    patch "/cs-studio/tree", params: { page_id: @child.id, parent_id: @b.id, position: 0 },
      headers: { "X-Page-Base-Updated-At" => @child.settings_changed_at.iso8601(6) }, as: :turbo_stream
    assert_response :success
    assert_not_includes response.body, "page-base-updated-at"
  end

  test "a move answers with an Undo toast that puts the page back where it was" do
    # @child was alone under @a (rank 0); drop it under @b at rank 0.
    patch "/cs-studio/tree", params: { page_id: @child.id, parent_id: @b.id, position: 0 }, as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[action='append'][target='toasts'] .admin-toast[data-kind='undo']", text: /Moved .Child./
    undo = css_select("turbo-stream[target='toasts'] form").first
    assert_equal "patch", css_select(undo, "input[name='_method']").first["value"]
    undo_query = Rack::Utils.parse_nested_query(URI.parse(undo["action"]).query)
    assert_equal({ "page_id" => @child.id.to_s, "parent_id" => @a.id.to_s, "position" => "0", "undo" => "1" }, undo_query)

    # Posting that form's own URL goes through the ordinary service again.
    patch undo["action"], as: :turbo_stream
    assert_response :success
    assert_equal @a, @child.reload.parent
    # An Undo is confirmed plainly: no second Undo to bounce between the two.
    assert_select "turbo-stream[target='toasts'] .admin-toast", text: /undone/i
    assert_select "turbo-stream[target='toasts'] .admin-toast form", count: 0
  end

  test "Undo records the rank among siblings, not the stored position" do
    third = create_page(title: "Third")
    patch "/cs-studio/tree", params: { page_id: @a.id, parent_id: root_page.id, position: 2 }, as: :turbo_stream
    undo = css_select("turbo-stream[target='toasts'] form").first
    assert_equal "0", Rack::Utils.parse_nested_query(URI.parse(undo["action"]).query)["position"]
    patch undo["action"], as: :turbo_stream
    assert_equal [ @a, @b, third ], root_page.reload.children.order(:position).to_a
  end

  test "a drop that changes nothing offers no Undo" do
    patch "/cs-studio/tree", params: { page_id: @a.id, parent_id: root_page.id, position: 0 }, as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[target='toasts']", count: 0
  end

  test "a refused move offers no Undo" do
    patch "/cs-studio/tree", params: { page_id: @a.id, parent_id: @child.id, position: 0 }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_select "turbo-stream[target='toasts']", count: 0
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

  # Handoff §10 B24: "↻N" for outdated and "○N" for missing fields, summed
  # over the target languages, the tooltip naming them; nothing at zero.
  test "the tree counts missing translations, naming the languages" do
    with_locales(%w[en de es], default: "en")
    assert Pages::Save.call(@a, translations: { "es" => { title: "Alfa" } }).ok?
    assert Pages::Save.call(@b, translations: { "de" => { title: "Beta" }, "es" => { title: "Beta" } }).ok?

    get "/cs-studio/pages/#{@b.id}"

    assert_select "turbo-frame#tree li[data-page-id='#{@a.id}'] > div [data-translation-marker]", count: 1 do |markers|
      assert_equal "○1", markers.first.text
      assert_equal "Deutsch: 1 missing", markers.first["title"]
      assert_equal "1 missing translation: Deutsch", markers.first["aria-label"]
    end
    assert_select "turbo-frame#tree li[data-page-id='#{@b.id}'] > div [data-translation-marker]", count: 0
  end

  test "the tree counts outdated fields too" do
    with_locales(%w[en de es], default: "en")
    assert Pages::Save.call(@b, translations: { "de" => { title: "Beta" } }).ok?
    assert Pages::Save.call(@b, translations: { "en" => { title: "Beta!" } }).ok?

    get "/cs-studio/pages/#{@a.id}"

    assert_select "turbo-frame#tree li[data-page-id='#{@b.id}'] > div [data-translation-marker=outdated]", text: "↻1" do |markers|
      assert_equal "Deutsch: 1 outdated", markers.first["title"]
    end
    assert_select "turbo-frame#tree li[data-page-id='#{@b.id}'] > div [data-translation-marker=missing]", text: "○1" do |markers|
      assert_equal "Español: 1 missing", markers.first["title"]
    end
  end

  test "the tree shows no marker with one language enabled" do
    with_locales(%w[en], default: "en")

    get "/cs-studio/pages/#{@a.id}"

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
      # Nor presence's marker element, shown or hidden: nothing is asked
      # about a page the viewer may not read.
      assert_nil rows.first.at_css("[data-presence-marker]")
    end
    assert_select "turbo-frame#tree [data-presence-marker='page-#{root_page.id}']", count: 0
    assert_select "turbo-frame#tree li[data-page-id='#{@a.id}'] > div > [data-presence-marker='page-#{@a.id}']"
    assert_select "turbo-frame#tree li[data-page-id='#{@a.id}'] > div [data-translation-marker]"
  end
end
