require "test_helper"

class Trash::RestoreTest < ActiveSupport::TestCase
  setup { Current.actor = users(:one) }

  test "a branch comes back together with its URLs" do
    parent = create_page(title: "Section")
    child = create_page(title: "Child", parent: parent)
    Trash::Move.call(parent)

    result = Trash::Restore.call(parent.reload)
    assert result.ok?, result.errors.to_sentence
    assert_equal parent, result.record
    [ parent, child ].each do |page|
      page.reload
      assert_not page.trashed?
      assert_nil page.trash_root_id
      assert_nil page.trashed_by_id
    end
    assert_equal "/section", PublicSite::Paths.current_path(parent, Locales.default)
    assert_equal "/section/child", PublicSite::Paths.current_path(child, Locales.default)
  end

  test "a descendant trashed separately stays in the trash" do
    parent = create_page(title: "Section")
    child = create_page(title: "Child", parent: parent)
    Trash::Move.call(child)
    Trash::Move.call(parent.reload)
    assert Trash::Restore.call(parent.reload).ok?
    assert child.reload.trashed?
    assert_equal child.id, child.trash_root_id
    assert_nil PublicSite::Paths.current_path(child, Locales.default)
  end

  test "a page trashed on its own under a kept parent restores in place, at its old rank" do
    parent = create_page(title: "Section")
    first = create_page(title: "First", parent: parent)
    middle = create_page(title: "Middle", parent: parent)
    last = create_page(title: "Last", parent: parent)
    Trash::Move.call(middle)

    assert Trash::Restore.call(middle.reload).ok?
    assert_equal parent, middle.reload.parent
    assert_equal [ first, middle, last ], Page.kept.where(parent_id: parent.id).order(:position, :id).to_a
    assert_equal "/section/middle", PublicSite::Paths.current_path(middle, Locales.default)
  end

  test "a page whose parent went to the trash later needs its parent back first" do
    parent = create_page(title: "Section")
    child = create_page(title: "Child", parent: parent)
    Trash::Move.call(child)
    Trash::Move.call(parent.reload)

    refused = Trash::Restore.call(child.reload)
    assert_not refused.ok?
    assert_equal [ "Its parent page is in the trash: restore that first, or choose a new parent" ], refused.errors
    assert child.reload.trashed?
  end

  test "a subpage alone is refused while its branch root is trashed, and works with a new parent" do
    parent = create_page(title: "Section")
    child = create_page(title: "Child", parent: parent)
    other = create_page(title: "Elsewhere")
    create_page(title: "Existing", parent: other)
    Trash::Move.call(parent)

    refused = Trash::Restore.call(child.reload)
    assert_not refused.ok?
    assert_equal [ "Restore “Section” to bring this page back, or choose a new parent" ], refused.errors
    assert child.reload.trashed?

    assert Trash::Restore.call(child.reload, parent: other).ok?
    assert_equal other, child.reload.parent
    assert_not child.trashed?
    assert_nil child.trash_root_id
    assert parent.reload.trashed?
    assert_equal %w[Existing Child], Page.kept.where(parent_id: other.id).order(:position, :id).map(&:title)
    assert_equal "/elsewhere/child", PublicSite::Paths.current_path(child, Locales.default)
  end

  test "a new parent can't be the page itself, one of its descendants, or a trashed page" do
    parent = create_page(title: "Section")
    child = create_page(title: "Child", parent: parent)
    Trash::Move.call(parent)
    assert_not Trash::Restore.call(parent.reload, parent: parent.reload).ok?
    assert_not Trash::Restore.call(parent.reload, parent: child.reload).ok?

    gone = create_page(title: "Gone")
    Trash::Move.call(gone)
    refused = Trash::Restore.call(parent.reload, parent: gone.reload)
    assert_not refused.ok?
    assert_equal [ "Choose a page that isn't in the trash" ], refused.errors
    assert parent.reload.trashed?
  end

  test "a page whose parent was purged needs a new parent" do
    parent = create_page(title: "Section")
    child = create_page(title: "Child", parent: parent)
    Trash::Move.call(child)                  # child is its own root
    child.update_columns(parent_id: nil)     # simulate: parent row gone (purge of parent tested in Task 7)
    refused = Trash::Restore.call(child.reload)
    assert_not refused.ok?
    assert_equal [ "Its parent page no longer exists: choose a new parent" ], refused.errors
  end

  test "a slug taken meanwhile gets the next free suffix, per locale" do
    with_locales(%w[en de], default: "en") do
      page = create_page(title: "About", translations: { "de" => { title: "Über", slug: "ueber" } })
      Trash::Move.call(page)
      create_page(title: "About again", translations: { "en" => { title: "About again", slug: "about" }, "de" => { title: "Anders", slug: "anders" } })
      create_page(title: "About 2", translations: { "en" => { title: "About 2", slug: "about-2" }, "de" => { title: "Zwei", slug: "zwei" } })

      service = Trash::Restore.new(page.reload)
      assert service.call.ok?
      assert_equal "about-3", page.reload.slug_en
      assert_equal "ueber", page.slug_de
      assert_equal [ { record: page, locale: "en", from: "about", to: "about-3" } ], service.slug_changes
      assert_equal "/about-3", PublicSite::Paths.current_path(page, "en")
      assert_equal "/ueber", PublicSite::Paths.current_path(page, "de")
    end
  end

  test "a slug taken in one locale only is suffixed in that locale alone" do
    with_locales(%w[en de], default: "en") do
      page = create_page(title: "About", translations: { "de" => { title: "Über", slug: "ueber" } })
      Trash::Move.call(page)
      create_page(title: "Other", translations: { "en" => { title: "Other", slug: "other" }, "de" => { title: "Über", slug: "ueber" } })

      service = Trash::Restore.new(page.reload)
      assert service.call.ok?
      assert_equal "about", page.reload.slug_en
      assert_equal "ueber-2", page.slug_de
      assert_equal [ { record: page, locale: "de", from: "ueber", to: "ueber-2" } ], service.slug_changes
    end
  end

  test "a post restores with its URL, and posts a restored listing page lists get theirs back" do
    blog = create_page(title: "Blog")
    ContentBlocks::Save.call(ContentBlock.new(owner: blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } })
    post = create_post(title: "Hello")
    listed = create_post(title: "Listed")
    Trash::Move.call(post)
    Trash::Move.call(blog)
    assert_nil PublicSite::Paths.current_path(listed.reload, Locales.default)

    assert Trash::Restore.call(blog.reload).ok?
    assert_equal "/blog/listed", PublicSite::Paths.current_path(listed.reload, Locales.default)
    assert_nil PublicSite::Paths.current_path(post.reload, Locales.default)

    assert Trash::Restore.call(post.reload).ok?
    assert_equal "/blog/hello", PublicSite::Paths.current_path(post.reload, Locales.default)
  end

  test "images trashed after their page come back with it" do
    asset = create_media_asset
    unrelated = create_media_asset
    page = create_page(title: "Hero page")
    Pages::Save.call(page, attributes: { hero_media_asset_id: asset.id })
    Trash::Move.call(page)
    Trash::Move.call(asset.reload)
    Trash::Move.call(unrelated)

    service = Trash::Restore.new(page.reload)
    assert service.call.ok?
    assert_not asset.reload.trashed?
    assert unrelated.reload.trashed?
    assert_equal [ asset ], service.restored_assets
    event = Audit::Event.find_by(action: "page.restored", subject_id: page.id)
    assert_equal [ asset.id ], event.metadata["restored_asset_ids"]
  end

  test "an image restores on its own" do
    asset = create_media_asset
    Trash::Move.call(asset)
    assert Trash::Restore.call(asset.reload).ok?
    assert_not asset.reload.trashed?
    assert Audit::Event.where(action: "media.restored", subject_id: asset.id).exists?
  end

  test "records a restored event with the slug changes" do
    with_locales(%w[en], default: "en") do
      post = create_post(title: "Hello")
      Trash::Move.call(post)
      create_post(title: "Hello")
      assert Trash::Restore.call(post.reload).ok?
      event = Audit::Event.find_by(action: "post.restored", subject_id: post.id)
      assert event
      assert_equal [ { "record" => "Post##{post.id}", "locale" => "en", "from" => "hello", "to" => "hello-2" } ],
        event.metadata["slug_changes"]
    end
  end

  # Mirrors test/services/pages/move_test.rb and the `editor_branch` rows in
  # test/services/authorization_matrix_test.rb: a new parent needs
  # `pages.move` on the page where it stands and `pages.create` under the
  # target, on top of the `pages.delete` every restore needs.
  test "a new parent needs pages.move on the page and pages.create under the target" do
    a, b, page = as_owner do
      a = create_page(title: "Branch A")
      b = create_page(title: "Branch B")
      page = create_page(title: "Doomed", parent: a)
      Trash::Move.call(page)
      [ a, b, page.reload ]
    end
    grant = ->(key, root) { AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: key, scope: { "page_ids" => [ root.id ] }) }
    grant.("pages.delete", a)
    grant.("pages.create", b)

    no_move = as(users(:editor_branch)) { Trash::Restore.call(page, parent: b) }
    assert no_move.denied?
    assert_equal [ "You don't have permission to #{AccessControl::Permissions.fetch("pages.move").label.downcase}" ], no_move.errors

    AccessControl::Grant.where(group: access_control_groups(:branch_editors), permission: "pages.create").delete_all
    grant.("pages.move", a)
    grant.("pages.create", a)
    no_create = as(users(:editor_branch)) { Trash::Restore.call(page.reload, parent: b) }
    assert no_create.denied?
    assert_equal [ "You don't have permission to #{AccessControl::Permissions.fetch("pages.create").label.downcase}" ], no_create.errors
    assert page.reload.trashed?
    assert_equal a, page.parent

    grant.("pages.create", b)
    assert as(users(:editor_branch)) { Trash::Restore.call(page.reload, parent: b) }.ok?
    assert_equal b, page.reload.parent
  end

  test "restoring needs the item's delete right" do
    page = as_owner { create_page(title: "Doomed").tap { |p| Trash::Move.call(p) } }
    refused = as(users(:editor_branch)) { Trash::Restore.call(page.reload) }
    assert refused.denied?
    assert page.reload.trashed?
  end

  test "a failed save rolls the branch members back and leaves the record trashed" do
    parent = create_page(title: "Section")
    child = create_page(title: "Child", parent: parent)
    Trash::Move.call(parent)
    parent.reload
    parent.define_singleton_method(:save!) { |*| raise ActiveRecord::RecordInvalid, self }

    assert_not Trash::Restore.call(parent).ok?
    assert parent.trashed?
    assert_equal parent.id, parent.trash_root_id
    assert child.reload.trashed?
    assert parent.reload.trashed?
    assert_not Audit::Event.where(action: "page.restored").exists?
  end

  test "restoring a kept record is refused" do
    post = create_post(title: "Here")
    refused = Trash::Restore.call(post)
    assert_not refused.ok?
    assert_equal [ "It isn't in the trash" ], refused.errors
  end
end
