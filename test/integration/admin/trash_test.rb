require "test_helper"

# The Trash screen (trash spec §7, Task 9): the list (newest first, who,
# when, the purge countdown, subpages), the type filter, restore (in place,
# with a slug change, under a new parent), permanent delete, Empty trash,
# what each viewer sees, the sidebar entry, and "not found, not forbidden"
# for an id that isn't in the trash or isn't of the addressed type.
class Admin::TrashTest < ActionDispatch::IntegrationTest
  setup do
    Current.actor = users(:one)
    @section = create_page(title: "Section")
    @child = create_page(title: "Child", parent: @section)
    @post = create_post(title: "Gone post")
    @asset = create_media_asset
    [ @section, @post, @asset ].each { |r| Trash::Move.call(r) }
    Current.reset
  end

  test "lists trashed items newest first with who, when and the purge countdown" do
    sign_in_as users(:one)
    get admin_trash_path
    assert_response :ok
    assert_select "tr", text: /Section/
    assert_select "tr", text: /\+1 subpage/
    assert_select "tr", text: /Gone post/
    assert_match "Deleted permanently in 30 days", response.body
    assert_select "tr", text: /Trashed by one@example.com/

    titles = css_select("tbody tr").map { |row| row["id"] }
    assert_equal [ "trash-media-#{@asset.id}", "trash-post-#{@post.id}", "trash-page-#{@section.id}" ], titles
  end

  test "filters by type" do
    sign_in_as users(:one)
    get admin_trash_path(type: "post")
    assert_select "tr", text: /Gone post/
    assert_select "tr", text: /Section/, count: 0
  end

  test "pages past the first 50 items" do
    Current.set(actor: users(:one)) do
      51.times { |n| Trash::Move.call(create_post(title: "Extra #{n}")) }
    end
    sign_in_as users(:one)

    get admin_trash_path
    assert_select "tbody tr", count: 50
    assert_select "nav[aria-label='Pagination'] a[rel=next]", text: "Next"
    assert_select "nav[aria-label='Pagination']", text: /1–50 OF 54/

    get admin_trash_path(page: 2)
    assert_select "tbody tr", count: 4
    assert_select "tr", text: /Section/
  end

  test "junk and out-of-range page numbers never error" do
    sign_in_as users(:one)
    %w[0 abc -1].each do |junk|
      get admin_trash_path(page: junk)
      assert_response :success
    end
    get admin_trash_path(page: 9999)
    assert_response :success
    assert_select "a", text: "Back to page 1"
  end

  # A page past the end has nothing to list, so nothing is loaded for it:
  # the window `listed_items` reads is `offset + 50` rows per type, i.e.
  # everything in the trash for a large enough `?page=`.
  test "an out-of-range page loads no trashed rows" do
    sign_in_as users(:one)
    row_queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      row_queries << payload[:sql] if payload[:sql].match?(/ORDER BY .*trashed_at.* DESC/i)
    end
    get admin_trash_path(page: 9999)
    assert_response :success
    assert_empty row_queries

    row_queries.clear
    get admin_trash_path
    assert_not_empty row_queries, "the probe does see the list's own queries on a real page"
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  test "restore brings an item back and says where" do
    sign_in_as users(:one)
    post admin_restore_trash_item_path("post", @post)
    assert_redirected_to admin_trash_path
    assert_not @post.reload.trashed?
    follow_redirect!
    assert_match "Restored “Gone post”", response.body
  end

  test "restore with a slug change names the new slug" do
    Current.set(actor: users(:one)) { create_page(title: "Section") }
    sign_in_as users(:one)
    post admin_restore_trash_item_path("page", @section)
    follow_redirect!
    assert_match "as section-2 (the URL was taken)", response.body
  end

  test "a subpage needs a parent: the form offers kept pages" do
    Current.set(actor: users(:one)) do
      Trash::Restore.call(@section.reload)
      Trash::Move.call(@child.reload)
      Trash::Move.call(@section.reload)   # now child is its own root inside a trashed parent
    end
    sign_in_as users(:one)
    get admin_trash_path
    assert_select "select[name=parent_id]"
    other = Current.set(actor: users(:one)) { create_page(title: "Elsewhere") }
    post admin_restore_trash_item_path("page", @child), params: { parent_id: other.id }
    assert_equal other, @child.reload.parent
  end

  test "a refused restore comes back as an alert" do
    Current.set(actor: users(:one)) do
      Trash::Restore.call(@section.reload)
      Trash::Move.call(@child.reload)
      Trash::Move.call(@section.reload)
    end
    sign_in_as users(:one)
    post admin_restore_trash_item_path("page", @child)
    assert_redirected_to admin_trash_path
    follow_redirect!
    assert_select "[role=alert]", text: /Its parent page is in the trash/
    assert @child.reload.trashed?
  end

  test "purge deletes one item for good" do
    sign_in_as users(:one)
    delete admin_trash_item_path("post", @post)
    assert_not Post.exists?(@post.id)
    follow_redirect!
    assert_match "Deleted “Gone post” permanently", response.body
  end

  # The confirm dialog says what else goes: every page under the root, a
  # descendant trashed separately earlier included -- the same set
  # `Trash::Purge` destroys -- while a post's says nothing of subpages.
  test "a page's delete dialog counts every subpage that goes with it" do
    Current.set(actor: users(:one)) do
      Trash::Restore.call(@section.reload)
      grandchild = create_page(title: "Grandchild", parent: @child)
      Trash::Move.call(grandchild)
      Trash::Move.call(@section.reload)
    end
    sign_in_as users(:one)
    get admin_trash_path
    assert_select "dialog#purge-page-#{@section.id}", text: /2 subpages under it are deleted too/
    assert_select "dialog#purge-post-#{@post.id}", text: /subpage/, count: 0
  end

  test "an image still used by a trashed item can't be deleted permanently from the list" do
    Current.set(actor: users(:one)) do
      Trash::Restore.call(@asset.reload)
      Trash::Restore.call(@section.reload)
      Pages::Save.call(@section.reload, attributes: { hero_media_asset_id: @asset.id })
      Trash::Move.call(@section.reload)
      Trash::Move.call(@asset.reload)
    end
    sign_in_as users(:one)
    get admin_trash_path(type: "media")
    assert_select "#trash-media-#{@asset.id} button[disabled][title='Still used by an item in the trash']"
  end

  test "empty trash needs trash.empty and removes everything" do
    sign_in_as users(:two)   # Admin group: holds trash.empty via the fixture grant
    delete admin_empty_trash_path
    assert_equal 0, Post.trashed.count + Page.trashed.count + Media::Asset.trashed.count
    follow_redirect!
    assert_match "Emptied the trash: 3 deleted permanently", response.body
  end

  test "empty trash is refused without trash.empty" do
    grant = access_control_grants(:admin_trash_empty)
    grant.destroy!
    sign_in_as users(:two)
    get admin_trash_path
    assert_select "button", text: "Empty trash", count: 0
    delete admin_empty_trash_path
    assert_response :forbidden
    assert @post.reload.trashed?
  end

  test "a viewer sees only what they could restore" do
    sign_in_as users(:author)
    get admin_trash_path
    assert_select "tr", text: /Gone post/, count: 0   # author may delete only their own posts
  end

  test "an uploader with media.upload sees their own trashed image, not someone else's" do
    own = Current.set(actor: users(:author)) { create_media_asset.tap { |a| a.update!(created_by: users(:author), title: "Mine") } }
    Current.set(actor: users(:one)) { Trash::Move.call(own) }
    sign_in_as users(:author)
    get admin_trash_path
    assert_select "#trash-media-#{own.id}"
    assert_select "#trash-media-#{@asset.id}", count: 0
  end

  test "the Trash screen is 403 without any delete right" do
    sign_in_as users(:reader)
    get admin_trash_path
    assert_response :forbidden
  end

  test "the sidebar shows Trash to holders of any delete right, not to a reader" do
    sign_in_as users(:reader)
    get admin_root_path
    assert_select "nav[aria-label='Modules'] a", text: /\ATrash/, count: 0
    sign_in_as users(:two)
    get admin_root_path
    assert_select "nav[aria-label='Modules'] a", text: /\ATrash/
  end

  test "a trashed id outside the trash, or of the wrong type, 404s" do
    sign_in_as users(:one)
    kept = Current.set(actor: users(:one)) { create_post(title: "Kept") }
    post admin_restore_trash_item_path("post", kept)
    assert_response :not_found
    post admin_restore_trash_item_path("page", @post)
    assert_response :not_found
  end

  # The sidebar's Trash badge (design pass spec §4): the same delete-right
  # scopes the screen lists with, so each viewer's number is what they'd
  # see on the Trash screen itself -- an owner counts the page branch (one
  # root, not its members), the post and the image; an author holding only
  # `media.upload` counts just the images they uploaded.
  test "the sidebar's Trash badge counts what this viewer could act on" do
    mine = create_media_asset
    mine.update!(created_by_id: users(:author).id)
    Current.set(actor: users(:one)) { Trash::Move.call(mine) }

    sign_in_as users(:one)
    get admin_root_path
    assert_select "nav[aria-label='Modules'] a[href='#{admin_trash_path}'] [data-badge]", text: "4"

    sign_in_as users(:author)
    get admin_root_path
    assert_select "nav[aria-label='Modules'] a[href='#{admin_trash_path}'] [data-badge]", text: "1"
    get admin_trash_path
    assert_select "[id^=trash-]", count: 1
  end

  test "an empty trash shows no badge" do
    Current.set(actor: users(:one)) { Trash::Empty.call }
    sign_in_as users(:one)
    get admin_root_path
    assert_select "nav[aria-label='Modules'] a[href='#{admin_trash_path}']"
    assert_select "nav[aria-label='Modules'] [data-badge]", count: 0
  end
end
