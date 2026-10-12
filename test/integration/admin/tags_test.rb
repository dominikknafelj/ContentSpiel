require "test_helper"

class Admin::TagsTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    sign_in_as(users(:one))
  end

  test "the list shows every tag with its readable post count linking to the filtered posts list" do
    create_post(title: "One", tags: [ "rails" ])
    create_post(title: "Two", tags: [ "rails" ])
    create_post(title: "Three", tags: [ "ruby" ])
    tag = Tag.find_by!(name: "rails")

    get "/cs-studio/tags"
    assert_response :success
    assert_select "tr##{ActionView::RecordIdentifier.dom_id(tag)}" do
      assert_select "input[name='tag[name]'][value='rails']"
      assert_select "a[href=?]", "/cs-studio/posts?tag=rails", text: "2 posts"
    end
    assert_select "tr##{ActionView::RecordIdentifier.dom_id(Tag.find_by!(name: "ruby"))} a", text: "1 post"
  end

  test "a tag name with spaces, an ampersand, a hash and quotes survives into the posts link" do
    name = %(a b & c #1 "q")
    create_post(title: "One", tags: [ name ])
    tag = Tag.find_by!(name: name)

    get "/cs-studio/tags"

    href = css_select("tr##{ActionView::RecordIdentifier.dom_id(tag)} a[href^='/cs-studio/posts']").first["href"]
    assert_equal name, Rack::Utils.parse_query(URI.parse(href).query)["tag"]
    get href
    assert_response :success
    assert_select "tbody th a", text: /One/
  end

  # A trashed post isn't one of the tag's posts as far as the list is concerned.
  test "the post count leaves out trashed posts" do
    create_post(title: "One", tags: [ "rails" ])
    create_post(title: "Two", tags: [ "rails" ]).update_columns(trashed_at: Time.current)
    tag = Tag.find_by!(name: "rails")

    get "/cs-studio/tags"
    assert_response :success
    assert_select "tr##{ActionView::RecordIdentifier.dom_id(tag)}" do
      assert_select "a", text: "1 post"
      assert_select "a", text: "2 posts", count: 0
    end
  end

  test "a tag manager who cannot read posts sees no count and no link, only the neutral dialog copy" do
    create_post(title: "One", tags: [ "rails" ])
    tag = Tag.find_by!(name: "rails")
    sign_in_as(tag_manager("tags.manage" => {}))

    get "/cs-studio/tags"
    assert_response :success
    assert_select "tr##{ActionView::RecordIdentifier.dom_id(tag)}" do
      assert_select "a[href*='/posts']", count: 0
      assert_select "button[data-tag-delete-text=?]", "It is removed from every post that uses it. The posts themselves stay."
    end
  end

  test "the count is what the viewer may read, while the dialogs name every post the action reaches" do
    create_post(title: "Blog", content_type: "blog", tags: [ "rails" ])
    create_post(title: "Entry", content_type: "resume_entry", tags: [ "rails" ])
    tag = Tag.find_by!(name: "rails")
    sign_in_as(tag_manager("tags.manage" => {}, "posts.read" => { "content_types" => [ "blog" ] }))

    get "/cs-studio/tags"
    assert_select "tr##{ActionView::RecordIdentifier.dom_id(tag)}" do
      assert_select "a[href*='tag=rails']", text: "1 post"
      # Two numbers for one tag need a reason (final fix wave, Task 13 I1).
      assert_select "button[data-tag-delete-text=?]", "It is removed from 2 posts, including ones in the trash or that you can't open. The posts themselves stay."
      assert_select "button[data-tag-merge-text=?]", "Its 2 posts, including ones in the trash or that you can't open, get the chosen tag and “rails” is deleted. This can't be undone."
    end
  end

  test "when the column and the dialog agree, the dialogs keep the plain sentences; a single hidden post is named in the singular" do
    create_post(title: "One", tags: [ "rails" ])
    create_post(title: "Two", tags: [ "rails" ])
    create_post(title: "Only hidden", tags: [ "gone" ]).update_columns(trashed_at: Time.current)

    get "/cs-studio/tags"
    assert_select "tr##{ActionView::RecordIdentifier.dom_id(Tag.find_by!(name: "rails"))}" do
      assert_select "button[data-tag-delete-text=?]", "It is removed from 2 posts. The posts themselves stay."
      assert_select "button[data-tag-merge-text=?]", "Its 2 posts get the chosen tag and “rails” is deleted. This can't be undone."
    end
    assert_select "tr##{ActionView::RecordIdentifier.dom_id(Tag.find_by!(name: "gone"))}" do
      assert_select "button[data-tag-delete-text=?]", "It is removed from 1 post, which is in the trash or one you can't open. The posts themselves stay."
      assert_select "button[data-tag-merge-text=?]", "Its 1 post, which is in the trash or one you can't open, gets the chosen tag and “gone” is deleted. This can't be undone."
    end
  end

  test "the post counts come from one grouped query however many tags there are" do
    get "/cs-studio/tags" # the session's first request loads a few things later ones don't
    2.times { |i| create_post(title: "P#{i}", tags: [ "tag#{i}" ]) }
    few = count_queries { get "/cs-studio/tags" }
    10.times { |i| create_post(title: "Q#{i}", tags: [ "more#{i}", "tag0" ]) }
    many = count_queries { get "/cs-studio/tags" }

    assert_equal few, many
  end

  test "an empty tag list shows the empty state" do
    get "/cs-studio/tags"
    assert_response :success
    assert_select "h1", "Tags"
    assert_select "h3", "No tags yet"
  end

  test "inline rename answers a saved status stream and resyncs listed posts" do
    listing = create_page(title: "Rails posts")
    ContentBlocks::Save.call(listing.content_blocks.build, attributes: { block_type: "post_list", settings: { content_type: "blog", tag: "rails" } })
    post = create_post(title: "Hi", tags: [ "rails" ])
    tag = Tag.find_by!(name: "rails")
    follow_rows! # the service's own sync, which acts on the rows: with copies nothing moves until they are published
    assert_equal "/rails-posts/hi", post.full_path("en")

    patch "/cs-studio/tags/#{tag.id}", params: { tag: { name: "ruby" }, base_updated_at: tag.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :success
    assert_match(/SAVED( · NOT PUBLISHED)? \d\d:\d\d/, response.body)
    assert_equal "ruby", tag.reload.name
    assert_nil post.reload.full_path("en")
  end

  test "a rename on a stale base still saves, and says so without the refusal's wording" do
    tag = Tag.create!(name: "rails")
    stale = tag.updated_at.iso8601(6)
    travel 1.minute
    tag.update!(name: "rails2")

    patch "/cs-studio/tags/#{tag.id}", params: { tag: { name: "ruby" }, base_updated_at: stale }, as: :turbo_stream
    assert_response :success
    assert_equal "ruby", tag.reload.name
    assert_match(/SAVED · ALSO CHANGED ELSEWHERE — RELOAD TO SEE THE LATEST/, response.body)
    assert_no_match(/● CHANGED ELSEWHERE/, response.body)
  end

  test "renaming to a name already taken comes back as a per-field error" do
    Tag.create!(name: "rails")
    other = Tag.create!(name: "ruby")

    patch "/cs-studio/tags/#{other.id}", params: { tag: { name: "rails" }, base_updated_at: other.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_match(/Couldn.*?t save — 1 problem(?!s)/, response.body)
    assert_match(/has already been taken/, response.body)
    assert_equal "ruby", other.reload.name
  end

  # What the dialogs say is the number of posts the action really reaches: every
  # post carrying the tag, trashed ones included (what `tag.merged` records too),
  # not only the readable ones the list counts.
  test "the dialogs are filled from each row's trigger with the true carrier count" do
    create_post(title: "One", tags: [ "rails" ])
    create_post(title: "Two", tags: [ "rails" ])
    create_post(title: "Gone", tags: [ "rails" ]).update_columns(trashed_at: Time.current)
    tag = Tag.find_by!(name: "rails")

    get "/cs-studio/tags"
    assert_response :success
    assert_select "tr##{ActionView::RecordIdentifier.dom_id(tag)}" do
      assert_select "button[data-tag-delete-title=?][data-tag-delete-text=?]",
        "Delete “rails”?", "It is removed from 3 posts, including ones in the trash or that you can't open. The posts themselves stay."
      assert_select "button[data-tag-merge-title=?][data-tag-merge-text=?]",
        "Merge “rails” into…", "Its 3 posts, including ones in the trash or that you can't open, get the chosen tag and “rails” is deleted. This can't be undone."
    end
  end

  test "an unused tag says no posts use it" do
    tag = Tag.create!(name: "unused")

    get "/cs-studio/tags"
    assert_select "tr##{ActionView::RecordIdentifier.dom_id(tag)} button[data-tag-delete-text=?]", "No posts use it."
  end

  test "there is one merge dialog and one delete dialog, outside every form but their own" do
    create_post(title: "One", tags: [ "rails" ])
    create_post(title: "Two", tags: [ "ruby" ])

    get "/cs-studio/tags"

    assert_select "dialog#merge-tag-dialog", count: 1
    assert_select "dialog#delete-tag-dialog", count: 1
    assert_select "form dialog", count: 0
    assert_select "dialog#merge-tag-dialog form#merge-tag-form" do
      assert_select "[data-controller='admin--ui--chip-input'][data-admin--ui--chip-input-single-value='true'][data-admin--ui--chip-input-create-value='false']"
    end
    assert_select "dialog#merge-tag-dialog footer button[type=submit][form='merge-tag-form'][disabled]", text: "Merge tags"
    assert_select "dialog#merge-tag-dialog [data-merge-published-lists]",
      text: "A merge changes published lists at once, without “Publish changes…”: posts with the merged tag join the lists that show the chosen tag, and a post with either tag can move to another address."
    # The picker's controls never sit inside a row's autosave form.
    assert_select "form[data-controller='admin--saving--autosave'] [data-controller='admin--ui--chip-input']", count: 0
    assert_select "dialog#delete-tag-dialog button.bg-danger", text: "Delete tag"
  end

  test "a row has a menu with Merge into… and Delete tag… and no red button" do
    create_post(title: "One", tags: [ "rails" ])
    tag = Tag.find_by!(name: "rails")

    get "/cs-studio/tags"

    assert_select "tr##{ActionView::RecordIdentifier.dom_id(tag)} [role=menu]" do
      assert_select "button", text: "Merge into…"
      assert_select "button", text: "Delete tag…"
    end
    assert_select "tr##{ActionView::RecordIdentifier.dom_id(tag)} button.text-danger-ink, tr##{ActionView::RecordIdentifier.dom_id(tag)} .bg-danger", count: 0
    assert_select "p", text: /Click a name to rename it/
  end

  test "a name over the limit is refused on the row" do
    tag = Tag.create!(name: "rails")

    patch "/cs-studio/tags/#{tag.id}", params: { tag: { name: "x" * (Tag::MAX_NAME_LENGTH + 1) }, base_updated_at: tag.updated_at.iso8601(6) }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_match(/too long/, response.body)
    assert_equal "rails", tag.reload.name
  end

  test "delete removes the tag, the join rows, and resyncs the listing it filtered" do
    listing = create_page(title: "Rails posts")
    ContentBlocks::Save.call(listing.content_blocks.build, attributes: { block_type: "post_list", settings: { content_type: "blog", tag: "rails" } })
    post = create_post(title: "Hi", tags: [ "rails" ])
    tag = Tag.find_by!(name: "rails")
    follow_rows! # the service's own sync, which acts on the rows: with copies nothing moves until they are published
    assert_equal "/rails-posts/hi", post.full_path("en")

    delete "/cs-studio/tags/#{tag.id}", as: :turbo_stream
    assert_response :success
    assert_not Tag.exists?(tag.id)
    assert_empty post.reload.tags
    assert_nil post.full_path("en")
  end

  # --- Merge ---------------------------------------------------------------

  test "merge gives the posts the target, deletes the source, and answers 303 with a toast" do
    one = create_post(title: "One", tags: [ "news" ])
    two = create_post(title: "Two", tags: [ "studio" ])
    source, into = Tag.find_by!(name: "news"), Tag.find_by!(name: "studio")

    post "/cs-studio/tags/#{source.id}/merge", params: { into: into.name }
    assert_redirected_to "/cs-studio/tags"
    assert_response :see_other
    assert_not Tag.exists?(source.id)
    assert_equal %w[studio], one.reload.tags.map(&:name)
    assert_equal %w[studio], two.reload.tags.map(&:name)

    follow_redirect!
    assert_select "#toasts", /Merged “news” into “studio”/
    assert_select "input[name='tag[name]'][value='news']", count: 0
    assert_select "a", text: "2 posts"
  end

  test "the merge toast escapes the tag names" do
    create_post(title: "One", tags: [ "<b>x</b>" ])
    source, into = Tag.find_by!(name: "<b>x</b>"), Tag.create!(name: "y")

    post "/cs-studio/tags/#{source.id}/merge", params: { into: into.name }
    follow_redirect!

    assert_includes response.body, "Merged “&lt;b&gt;x&lt;/b&gt;” into “y”"
    assert_no_match(%r{Merged “<b>}, response.body)
  end

  test "merge refuses the source as its own target, without a 500" do
    source = Tag.create!(name: "news")

    post "/cs-studio/tags/#{source.id}/merge", params: { into: "news" }
    assert_redirected_to "/cs-studio/tags"
    follow_redirect!
    assert_select "#toasts", /Choose a different tag to merge into/
    assert Tag.exists?(source.id)
  end

  test "merge with no target or a target that no longer exists is a plain refusal" do
    source = Tag.create!(name: "news")

    post "/cs-studio/tags/#{source.id}/merge", params: { into: "" }
    follow_redirect!
    assert_select "#toasts", /Choose a tag to merge into/

    post "/cs-studio/tags/#{source.id}/merge", params: { into: "vanished" }
    follow_redirect!
    assert_select "#toasts", /That tag no longer exists/
    assert Tag.exists?(source.id)
  end

  test "merging a source that was deleted in another tab is a 404, not a 500" do
    into = Tag.create!(name: "studio")

    post "/cs-studio/tags/#{Tag.maximum(:id).to_i + 100}/merge", params: { into: into.name }
    assert_response :not_found
  end

  test "merge without tags.manage is a 403 and changes nothing" do
    source = Tag.create!(name: "news")
    Tag.create!(name: "studio")
    sign_in_as(users(:reader))

    post "/cs-studio/tags/#{source.id}/merge", params: { into: "studio" }
    assert_response :forbidden
    assert Tag.exists?(source.id)
  end

  # Merge touches the carrying posts, the repointed blocks and their pages, so
  # whatever form of those is open resends the OLD tag name and would undo it.
  test "after a merge an open post form's save is a 409 and does not bring the source back" do
    post_record = create_post(title: "Engineer", tags: [ "ruby" ])
    stale = post_record.updated_at.iso8601(6)
    travel 2.seconds
    Tag.create!(name: "rails")

    post "/cs-studio/tags/#{Tag.find_by!(name: "ruby").id}/merge", params: { into: "rails" }

    patch "/cs-studio/posts/#{post_record.id}", params: { base_updated_at: stale, post: { title: "Engineer 2", tag_names: [ "", "ruby" ] } }, as: :turbo_stream
    assert_response :conflict
    assert_not Tag.exists?(name: "ruby")
    assert_equal %w[rails], post_record.reload.tags.map(&:name)
  end

  test "after a merge an open block card is refused as stale, and the page settings form, which the merge did not change, still saves" do
    page = create_page(title: "Rails posts")
    block = ContentBlocks::Save.call(page.content_blocks.build, attributes: { block_type: "post_list", settings: { content_type: "blog", tag: "ruby" } }).record
    create_post(title: "Hi", tags: [ "ruby" ])
    page_base = page.reload.settings_changed_at.iso8601(6)
    block_base = block.reload.updated_at.iso8601(6)
    travel 2.seconds
    Tag.create!(name: "rails")

    post "/cs-studio/tags/#{Tag.find_by!(name: "ruby").id}/merge", params: { into: "rails" }
    assert_equal "rails", block.reload.settings["tag"]

    patch "/cs-studio/pages/#{page.id}", params: { base_updated_at: page_base, page: { title: "Renamed" } }, as: :turbo_stream
    assert_response :success
    assert_equal "Renamed", page.reload.title

    patch "/cs-studio/pages/#{page.id}/content_blocks/#{block.id}", params: { base_updated_at: block_base, block: { settings: { tag: "ruby" } } }, as: :turbo_stream
    assert_response :conflict
    assert_equal "rails", block.reload.settings["tag"]
  end

  # Final fix wave (m3): the picker sends a name and the controller looked the
  # target up by the exact lowercased string, so a tag stored with a capital
  # (written before names were lowercased, or around the model) was "gone".
  test "the merge target is found whatever the case it is stored in" do
    create_post(title: "One", tags: [ "news" ])
    source = Tag.find_by!(name: "news")
    target = Tag.create!(name: "studio")
    target.update_columns(name: "Studio")

    post "/cs-studio/tags/#{source.id}/merge", params: { into: " STUDIO " }

    assert_redirected_to "/cs-studio/tags"
    assert_not Tag.exists?(source.id)
    assert_equal [ target.id ], Post.joins(:post_tags).where(post_tags: { tag_id: target.id }).map { |p| p.tags.map(&:id) }.flatten.uniq
    assert_equal "Merged “news” into “Studio”", flash[:notice]
  end

  # A tag name is whatever an editor typed; the delete toast repeats it.
  test "the delete toast escapes a tag name that contains markup" do
    tag = Tag.create!(name: "safe")
    tag.update_columns(name: "<img src=x onerror=alert(1)>")

    delete "/cs-studio/tags/#{tag.id}", as: :turbo_stream

    assert_response :success
    assert_not response.body.include?("<img src=x"), "the name reached the toast as markup"
    assert_includes response.body, "&lt;img src=x onerror=alert(1)&gt;"
  end

  test "the dialog's count and the event's count agree" do
    create_post(title: "One", tags: [ "news" ])
    create_post(title: "Two", tags: [ "news" ])
    create_post(title: "Gone", tags: [ "news" ]).update_columns(trashed_at: Time.current)
    source = Tag.find_by!(name: "news")
    Tag.create!(name: "studio")

    get "/cs-studio/tags"
    shown = css_select("tr##{ActionView::RecordIdentifier.dom_id(source)} button[data-tag-merge-text]").first["data-tag-merge-text"][/\d+/].to_i

    post "/cs-studio/tags/#{source.id}/merge", params: { into: "studio" }
    assert_equal shown, Audit::Event.find_by!(action: "tag.merged").metadata["posts"]
  end

  test "deleting answers a toast and leaves the dialog to be closed by the page" do
    tag = Tag.create!(name: "unused")

    delete "/cs-studio/tags/#{tag.id}", as: :turbo_stream
    assert_response :success
    assert_match(/Deleted “unused”/, response.body)
    assert_match(/action="remove"/, response.body)
  end

  private

  def tag_manager(grants)
    user = User.create!(email_address: "tags-#{SecureRandom.hex(3)}@example.org", password: "a-long-enough-password")
    group = AccessControl::Group.create!(name: "Tag managers #{SecureRandom.hex(3)}")
    grants.each { |permission, scope| AccessControl::Grant.create!(group: group, permission: permission, scope: scope) }
    AccessControl::Membership.create!(user: user, group: group)
    user
  end

  def count_queries(&block)
    queries = []
    counter = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" || payload[:cached] || payload[:sql].match?(/\A\s*(BEGIN|COMMIT|SAVEPOINT|RELEASE)/i) }
    # Counts what hits the database, not the query cache: a write just before
    # each measurement (the posts the test creates) empties that cache, so both
    # measurements start cold.
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    queries.size
  end
end
