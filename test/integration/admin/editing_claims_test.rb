require "test_helper"

# A SAVE IS A CLAIM (live-editing spec §4.2): the three autosave actions claim
# before they save and refuse a tab that does not hold the subject; `claim` and
# `release` are the two actions a tab calls ahead of and after a save.
class Admin::EditingClaimsTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper

  TAB_A = "tab-aaaaaaaa".freeze
  TAB_B = "tab-bbbbbbbb".freeze

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Pricing", published: false)
    # An image block: its caption is a plain translated column a save can change.
    @block = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "image" }).record
    @stream = Editing::Signals.record_stream(@page)
  end

  def autosave(block, text, tab: nil)
    patch admin_page_content_block_path(@page, block), as: :turbo_stream, headers: { "X-Notes-Tab" => tab }.compact,
      params: { base_updated_at: block.reload.updated_at.iso8601(6), block: { caption: text } }
  end

  def save_settings(title, tab: nil, page: @page)
    patch admin_page_path(page), as: :turbo_stream, headers: { "X-Notes-Tab" => tab }.compact,
      params: { base_updated_at: page.reload.settings_changed_at.iso8601(6), page: { title: title } }
  end

  def save_post(post, title, tab: nil)
    patch admin_post_path(post), as: :turbo_stream, headers: { "X-Notes-Tab" => tab }.compact,
      params: { base_updated_at: post.reload.updated_at.iso8601(6), post: { title: title } }
  end

  def claim(kind: "page", record: @page, block: nil, tab: nil)
    post admin_editing_claim_path(kind:, id: record.id), params: { block_id: block&.id }.compact, headers: { "X-Notes-Tab" => tab }.compact
  end

  def release(kind: "page", record: @page, block: nil, tab: nil)
    post admin_editing_release_path(kind:, id: record.id), params: { block_id: block&.id }.compact, headers: { "X-Notes-Tab" => tab }.compact
  end

  def holder_signals = broadcasts(@stream).map { |payload| ActiveSupport::JSON.decode(payload) }.select { |signal| signal["kind"] == "holder" }

  def expire_holds
    Editing::Reservation.update_all(changed_at: 3.minutes.ago) # version: none (a test moves a reservation's clock)
  end

  def limited_editor(*keys)
    keys.each { |key| AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: key, scope: {}) }
    users(:editor_branch)
  end

  test "a save claims the block for its tab, and a save from a tab that does not hold it is refused and writes nothing" do
    sign_in_as users(:one)
    autosave(@block, "mine", tab: TAB_A)
    assert_response :ok
    assert_equal [ users(:one).id, TAB_A ], Editing::Reservation.sole.values_at(:user_id, :tab)
    events = Audit::Event.count
    stamp = @block.reload.updated_at
    signals = holder_signals.size

    sign_in_as users(:two)
    autosave(@block, "theirs", tab: TAB_B)

    assert_response :conflict
    assert_equal "mine", @block.reload.caption
    assert_equal stamp, @block.updated_at
    assert_equal events, Audit::Event.count, "a refused save is not audited"
    assert_equal signals, holder_signals.size, "a refused save signals nothing"
    assert_select "turbo-stream[action=update][target='block-#{@block.id}-hold'] template [role=alert]", text: /is editing this block\. Your changes weren't saved\./
    assert_select "turbo-stream[target='block-#{@block.id}-save-status'] template", text: /Not saved/i
    assert_select "turbo-stream[target='block-#{@block.id}-save-status'] template", text: /IS EDITING/
    assert_no_match(/base-updated-at/, response.body, "a refusal hands back no base")
    assert_equal [ users(:one).id, TAB_A ], Editing::Reservation.sole.values_at(:user_id, :tab)
  end

  test "the status line names the holder in capitals, and the person's own other tab as such" do
    users(:one).update!(name: "Dana Weiss")
    sign_in_as users(:one)
    autosave(@block, "mine", tab: TAB_A)
    autosave(@block, "other tab", tab: TAB_B)

    assert_response :conflict
    assert_select "turbo-stream[target='block-#{@block.id}-save-status'] template", text: "● NOT SAVED · OPEN IN YOUR OTHER TAB"

    sign_in_as users(:two)
    autosave(@block, "theirs", tab: TAB_B)
    assert_select "turbo-stream[target='block-#{@block.id}-save-status'] template", text: "● NOT SAVED · DANA WEISS IS EDITING"
  end

  test "the holder's own other tab is refused like anyone else" do
    sign_in_as users(:one)
    autosave(@block, "first tab", tab: TAB_A)
    autosave(@block, "second tab", tab: TAB_B)

    assert_response :conflict
    assert_equal "first tab", @block.reload.caption
    assert_select "turbo-stream[target='block-#{@block.id}-save-status'] template", text: "● NOT SAVED · OPEN IN YOUR OTHER TAB"
  end

  test "a save with no tab id is saved and claims nothing, also while someone holds the block" do
    sign_in_as users(:one)
    autosave(@block, "script", tab: nil)
    assert_response :ok
    assert_equal 0, Editing::Reservation.count

    autosave(@block, "held", tab: TAB_A)
    sign_in_as users(:two)
    autosave(@block, "script again")

    assert_response :ok
    assert_equal "script again", @block.reload.caption
    assert_equal [ users(:one).id, TAB_A ], Editing::Reservation.sole.values_at(:user_id, :tab)
  end

  test "the page settings and a post are claimed and refused the same way, each by its own subject" do
    post_record = create_post(title: "Hello", published: false)
    sign_in_as users(:one)
    save_settings("Held title", tab: TAB_A)
    assert_response :ok

    sign_in_as users(:two)
    save_settings("Their title", tab: TAB_B)
    assert_response :conflict
    assert_equal "Held title", @page.reload.title
    assert_select "turbo-stream[target=page-hold] template [role=alert]", text: /is editing the page settings\./
    assert_select "turbo-stream[target=page-save-status] template", text: /IS EDITING/

    autosave(@block, "block is free", tab: TAB_B)
    assert_response :ok, "the settings' hold does not refuse a block"

    sign_in_as users(:one)
    autosave(@block, "settings holder, block held by the other", tab: TAB_A)
    assert_response :conflict, "and the block's hold does not let the settings' holder in"

    save_post(post_record, "Post by A", tab: TAB_A)
    assert_response :ok
    sign_in_as users(:two)
    save_post(post_record, "Post by B", tab: TAB_B)
    assert_response :conflict
    assert_equal "Post by A", post_record.reload.title
    assert_select "turbo-stream[target=editor-notice] template [role=alert]", text: /is editing this post\./
    assert_select "turbo-stream[target=post-save-status] template", text: /IS EDITING/
  end

  test "a section's settings form is its block's" do
    section = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "section", settings: { "layout" => "two" } }).record
    sign_in_as users(:one)
    patch admin_page_content_block_path(@page, section), as: :turbo_stream, headers: { "X-Notes-Tab" => TAB_A },
      params: { base_updated_at: section.reload.updated_at.iso8601(6), block: { settings: { layout: "three" } } }
    assert_response :ok
    assert_equal [ "ContentBlock", section.id ], Editing::Reservation.sole.values_at(:subject_type, :subject_id)

    sign_in_as users(:two)
    patch admin_page_content_block_path(@page, section), as: :turbo_stream, headers: { "X-Notes-Tab" => TAB_B },
      params: { base_updated_at: section.reload.updated_at.iso8601(6), block: { settings: { layout: "one" } } }
    assert_response :conflict
    assert_select "turbo-stream[target='block-#{section.id}-hold']"
  end

  test "an expired hold is taken by the next save, and the holder signal says claimed" do
    sign_in_as users(:one)
    autosave(@block, "mine", tab: TAB_A)
    expire_holds
    before = holder_signals.size

    sign_in_as users(:two)
    autosave(@block, "theirs", tab: TAB_B)

    assert_response :ok
    assert_equal "theirs", @block.reload.caption
    assert_equal [ users(:two).id, TAB_B ], Editing::Reservation.sole.values_at(:user_id, :tab)
    assert_equal [ { "kind" => "holder", "content_block_id" => @block.id, "reason" => "claimed", "origin" => TAB_B } ], holder_signals.drop(before)
  end

  test "a renewal signals nothing" do
    sign_in_as users(:one)
    autosave(@block, "one", tab: TAB_A)
    assert_equal 1, holder_signals.size

    autosave(@block, "two", tab: TAB_A)
    assert_response :ok
    assert_equal 1, holder_signals.size, "only the first save said claimed"
  end

  test "someone without the right to edit claims nothing: the save is the service's 403 and there is no row" do
    sign_in_as users(:reader)
    autosave(@block, "nope", tab: TAB_A)

    assert_response :forbidden
    assert_equal 0, Editing::Reservation.count
    assert_empty holder_signals
  end

  test "a published page needs publish to claim" do
    live = create_page(title: "Live", published: true)
    live_block = ContentBlocks::Save.call(ContentBlock.new(owner: live), attributes: { block_type: "image" }).record
    editor = limited_editor("pages.edit")
    sign_in_as editor

    post admin_editing_claim_path(kind: "page", id: live.id), headers: { "X-Notes-Tab" => TAB_A }
    assert_response :forbidden
    patch admin_page_content_block_path(live, live_block), as: :turbo_stream, headers: { "X-Notes-Tab" => TAB_A },
      params: { base_updated_at: live_block.reload.updated_at.iso8601(6), block: { caption: "x" } }
    assert_response :forbidden
    assert_equal 0, Editing::Reservation.count

    claim(tab: TAB_A)
    assert_response :no_content, "a draft needs edit only"
    assert_equal 1, Editing::Reservation.count
  end

  test "a stale save by a tab that took the block with this request lets it go again, and one by the holder keeps it" do
    sign_in_as users(:one)
    stale = @block.reload.updated_at.iso8601(6)
    travel(1.minute) { ContentBlocks::Save.call(@block, translations: { "en" => { caption: "elsewhere" } }) }

    patch admin_page_content_block_path(@page, @block), as: :turbo_stream, headers: { "X-Notes-Tab" => TAB_A },
      params: { base_updated_at: stale, block: { caption: "late" } }
    assert_response :conflict
    assert_equal "elsewhere", @block.reload.caption
    assert_equal 0, Editing::Reservation.count, "a refused form saves nothing more and must not hold the block"
    assert_equal %w[released], holder_signals.map { |signal| signal["reason"] }.last(1).presence || %w[released], "the claim it took was announced and given back"
    assert_equal %w[claimed released], holder_signals.map { |signal| signal["reason"] }

    autosave(@block, "mine", tab: TAB_A)
    assert_response :ok
    patch admin_page_content_block_path(@page, @block), as: :turbo_stream, headers: { "X-Notes-Tab" => TAB_A },
      params: { base_updated_at: stale, block: { caption: "late again" } }
    assert_response :conflict
    assert_equal [ users(:one).id, TAB_A ], Editing::Reservation.sole.values_at(:user_id, :tab), "the holder keeps what it held"
  end

  test "a refused hold is checked before the stale check" do
    sign_in_as users(:one)
    autosave(@block, "mine", tab: TAB_A)
    sign_in_as users(:two)
    patch admin_page_content_block_path(@page, @block), as: :turbo_stream, headers: { "X-Notes-Tab" => TAB_B },
      params: { base_updated_at: 1.day.ago.iso8601(6), block: { caption: "stale and refused" } }

    assert_response :conflict
    assert_select "turbo-stream[target='block-#{@block.id}-hold']"
    assert_select "turbo-stream[target=editor-notice]", false
  end

  test "claim: 204 and a row; 409 with the same streams when held; 403 for a reader; 404 outside the scope, for a trashed page and for another page's block" do
    sign_in_as users(:one)
    claim(block: @block, tab: TAB_A)
    assert_response :no_content
    assert_equal [ users(:one).id, TAB_A ], Editing::Reservation.sole.values_at(:user_id, :tab)
    assert_equal %w[claimed], holder_signals.map { |signal| signal["reason"] }

    claim(block: @block, tab: TAB_A)
    assert_response :no_content
    assert_equal 1, holder_signals.size, "a renewing claim signals nothing"

    sign_in_as users(:two)
    claim(block: @block, tab: TAB_B)
    assert_response :conflict
    assert_select "turbo-stream[target='block-#{@block.id}-hold'] template [role=alert]", text: /is editing this block/
    assert_select "turbo-stream[target='block-#{@block.id}-save-status']"

    claim(tab: TAB_B)
    assert_response :no_content, "the settings are a subject of their own"

    claim(block: @block)
    assert_response :no_content, "no tab id: nothing is claimed, nobody is refused"

    sign_in_as users(:reader)
    claim(block: @block, tab: "tab-cccccccc")
    assert_response :forbidden

    sign_in_as users(:one)
    other = create_page(title: "Other", published: false)
    other_block = ContentBlocks::Save.call(ContentBlock.new(owner: other), attributes: { block_type: "image" }).record
    claim(block: other_block, tab: TAB_A)
    assert_response :not_found
    post admin_editing_claim_path(kind: "page", id: 0), headers: { "X-Notes-Tab" => TAB_A }
    assert_response :not_found
    post admin_editing_claim_path(kind: "page", id: @page.id), params: { block_id: "abc" }, headers: { "X-Notes-Tab" => TAB_A }
    assert_response :not_found
    Trash::Move.call(other)
    claim(record: other, tab: TAB_A)
    assert_response :not_found
  end

  test "claim answers 404 for a page outside the viewer's read scope, never 403" do
    outside = create_page(title: "Outside", published: false)
    editor = limited_editor("pages.edit")
    AccessControl::Grant.where(group: access_control_groups(:branch_editors), permission: "pages.edit").destroy_all
    AccessControl::Grant.create!(group: access_control_groups(:branch_editors), permission: "pages.edit", scope: { "page_ids" => [ @page.id ] })
    sign_in_as editor

    claim(record: outside, tab: TAB_A)
    assert_response :not_found
    claim(tab: TAB_A)
    assert_response :no_content
  end

  test "release deletes the tab's own row and signals released; someone else's release deletes nothing and signals nothing" do
    sign_in_as users(:one)
    claim(block: @block, tab: TAB_A)
    before = holder_signals.size

    sign_in_as users(:two)
    release(block: @block, tab: TAB_B)
    assert_response :no_content
    assert_equal 1, Editing::Reservation.count
    assert_equal before, holder_signals.size

    sign_in_as users(:one)
    release(block: @block, tab: TAB_A)
    assert_response :no_content
    assert_equal 0, Editing::Reservation.count
    assert_equal [ { "kind" => "holder", "content_block_id" => @block.id, "reason" => "released", "origin" => TAB_A } ], holder_signals.drop(before)

    release(block: @block, tab: TAB_A)
    assert_response :no_content
    assert_equal before + 1, holder_signals.size, "releasing what is not held signals nothing"

    sign_in_as users(:reader)
    release(block: @block, tab: TAB_A)
    assert_response :forbidden
  end

  test "a block moved into a section while held is still held, by the same tab" do
    section = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "section", settings: { "layout" => "two" } }).record
    sign_in_as users(:one)
    autosave(@block, "mine", tab: TAB_A)
    row = Editing::Reservation.sole.attributes

    sign_in_as users(:two)
    patch reorder_admin_page_content_blocks_path(@page), as: :turbo_stream, headers: { "X-Notes-Tab" => TAB_B },
      params: { ids: [ @block.id ], section_id: section.id, column: 1, moved_from: { @block.id => { section_id: "", column: "" } } }
    assert_response :success
    assert_equal section.id, @block.reload.section_id

    assert_equal row, Editing::Reservation.sole.attributes, "the move neither took nor changed the hold"
    get admin_editing_block_path(kind: "page", id: @page.id, block_id: @block.id), headers: { "X-Notes-Tab" => TAB_B }
    assert_response :ok
    assert_select "#block-#{@block.id}-panel[data-editing-held]", text: /is editing this block/
  end

  test "moving, adding, duplicating and deleting ignore a hold" do
    other = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }).record
    sign_in_as users(:one)
    autosave(@block, "mine", tab: TAB_A)
    row = Editing::Reservation.sole.attributes

    sign_in_as users(:two)
    headers = { "X-Notes-Tab" => TAB_B }
    patch reorder_admin_page_content_blocks_path(@page), as: :turbo_stream, headers:, params: { ids: [ other.id, @block.id ] }
    assert_response :success
    post admin_page_content_blocks_path(@page), as: :turbo_stream, headers:, params: { block: { block_type: "rich_text" } }
    assert_response :success
    post duplicate_admin_page_content_block_path(@page, @block), as: :turbo_stream, headers: headers
    assert_response :success
    delete admin_page_content_block_path(@page, @block), as: :turbo_stream, headers: headers
    assert_response :success
    assert_nil ContentBlock.find_by(id: @block.id)
    assert_equal row.except("subject_id").keys, Editing::Reservation.sole.attributes.except("subject_id").keys
  end

  test "publish, unpublish and schedule are refused while another tab holds the post, and proceed, taking no hold, while it is free" do
    post_record = create_post(title: "Hello", published: false)
    sign_in_as users(:one)
    save_post(post_record, "Held", tab: TAB_A)
    events = Audit::Event.count

    sign_in_as users(:two)
    post publish_admin_post_path(post_record), headers: { "X-Notes-Tab" => TAB_B }
    assert_redirected_to admin_post_path(post_record)
    assert_match(/is editing this post/, flash[:alert])
    post schedule_admin_post_path(post_record), params: { published_at: 1.day.from_now.strftime("%Y-%m-%dT%H:%M") }, headers: { "X-Notes-Tab" => TAB_B }
    assert_match(/is editing this post/, flash[:alert])
    assert_equal "draft", post_record.reload.status
    assert_equal events, Audit::Event.count

    sign_in_as users(:one)
    post publish_admin_post_path(post_record), headers: { "X-Notes-Tab" => TAB_A }
    assert_equal "Published", flash[:notice], "the holder's own tab may publish"
    assert_predicate post_record.reload, :live?

    sign_in_as users(:two)
    post unpublish_admin_post_path(post_record), headers: { "X-Notes-Tab" => TAB_B }
    assert_match(/is editing this post/, flash[:alert])
    expire_holds
    post unpublish_admin_post_path(post_record), headers: { "X-Notes-Tab" => TAB_B }
    assert_equal "Unpublished", flash[:notice]
    assert_equal [ users(:one).id, TAB_A ], Editing::Reservation.sole.values_at(:user_id, :tab), "an instant action takes no hold of its own"
  end

  test "a page's publish while someone holds one of its blocks proceeds, and while someone holds the settings it is refused" do
    sign_in_as users(:one)
    autosave(@block, "held", tab: TAB_A)

    sign_in_as users(:two)
    post publish_admin_page_path(@page), headers: { "X-Notes-Tab" => TAB_B }
    assert_equal "Published", flash[:notice]
    assert_predicate @page.reload, :live?
    assert_equal 1, Editing::Reservation.count, "and it took no hold"

    sign_in_as users(:one)
    save_settings("Held title", tab: TAB_A)
    sign_in_as users(:two)
    post unpublish_admin_page_path(@page), headers: { "X-Notes-Tab" => TAB_B }
    assert_match(/is editing the page settings/, flash[:alert])
    assert_predicate @page.reload, :live?
  end

  test "an instant action without a tab id is never refused" do
    post_record = create_post(title: "Hello", published: false)
    sign_in_as users(:one)
    save_post(post_record, "Held", tab: TAB_A)
    sign_in_as users(:two)
    post publish_admin_post_path(post_record)

    assert_equal "Published", flash[:notice]
  end

  test "a publish-only person is refused only while someone holds the record, and is otherwise decided by the service" do
    post_record = create_post(title: "Hello", published: false)
    sign_in_as users(:one)
    save_post(post_record, "Held", tab: TAB_A)
    publisher = limited_editor("posts.publish", "posts.read")
    sign_in_as publisher

    claim(kind: "post", record: post_record, tab: TAB_B)
    assert_response :forbidden, "they cannot type, so they cannot claim"
    post publish_admin_post_path(post_record), headers: { "X-Notes-Tab" => TAB_B }
    assert_match(/is editing this post/, flash[:alert])
    expire_holds
    post publish_admin_post_path(post_record), headers: { "X-Notes-Tab" => TAB_B }
    assert_equal "Published", flash[:notice]
  end

  test "a translation confirmation is refused while another tab holds the record, and a free record is confirmed" do
    sign_in_as users(:one)
    save_post_holder = create_post(title: "Hello", published: false)
    save_post(save_post_holder, "Held", tab: TAB_A)
    sign_in_as users(:two)
    events = Audit::Event.count

    post admin_translation_confirmation_path, params: { record_type: "Post", record_id: save_post_holder.id, field: "title", locale: "de" },
      as: :turbo_stream, headers: { "X-Notes-Tab" => TAB_B }

    assert_response :conflict
    assert_includes response.body, "is editing this post"
    assert_equal events, Audit::Event.count
  end

  test "a write through the MCP channel holds nothing and is not refused" do
    sign_in_as users(:one)
    autosave(@block, "held", tab: TAB_A)
    token, = ApiToken.generate!(users(:two), group: access_control_groups(:admin), name: "Claude desktop")
    before = Editing::Reservation.count

    result = as(token, channel: :mcp) { ContentBlocks::Save.call(@block, translations: { "en" => { caption: "from mcp" } }) }

    assert_predicate result, :ok?
    assert_equal "from mcp", @block.reload.caption
    assert_equal before, Editing::Reservation.count
    assert_equal [ users(:one).id, TAB_A ], Editing::Reservation.sole.values_at(:user_id, :tab)
  end
end
