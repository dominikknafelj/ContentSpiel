require "test_helper"

class Admin::EditingTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Pricing", published: false)
    @block = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "image" }).record
    @section = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "section", settings: { "layout" => "two" } }).record
    @inside = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text", section_id: @section.id, section_column: 1 }).record
    @stranger = User.create!(email_address: "stranger@example.com", password: "a-long-password-1")
    sign_in_as users(:one)
  end

  test "the list is the page's cards, top-level blocks and the section with its tiles and panels, and nothing else of the page" do
    get admin_editing_blocks_path(kind: "page", id: @page.id)

    assert_response :ok
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_select "#content_block_#{@block.id}[data-editing-unit][data-editing-subject='block-#{@block.id}']"
    assert_select "#content_block_#{@section.id} #block-#{@inside.id}-panel[data-editing-unit][hidden]"
    assert_select "#content_block_#{@section.id} #content_block_#{@inside.id}[data-editing-part]"
    assert_select "#page-settings", false
    assert_select "html > head > title", false, "a fragment, not a page"
  end

  test "every answer, a 404 included, is kept by no cache" do
    [ admin_editing_blocks_path(kind: "page", id: @page.id), admin_editing_block_path(kind: "page", id: @page.id, block_id: @block.id),
      admin_editing_record_path(kind: "page", id: @page.id), admin_editing_record_path(kind: "page", id: 0) ].each do |path|
      get path
      assert_equal "no-store", response.headers["Cache-Control"], path
    end
    assert_response :not_found
  end

  test "a top-level block is its card; a block in a section is its tile and its panel; a section is 204" do
    get admin_editing_block_path(kind: "page", id: @page.id, block_id: @block.id)
    assert_select "#content_block_#{@block.id}[data-editing-unit]", 1

    get admin_editing_block_path(kind: "page", id: @page.id, block_id: @inside.id)
    assert_select "#content_block_#{@inside.id}[data-editing-part]", 1
    assert_select "#block-#{@inside.id}-panel[data-editing-unit]", 1

    get admin_editing_block_path(kind: "page", id: @page.id, block_id: @section.id)
    assert_response :no_content
  end

  test "on a translation tab the block's card is drawn in that language" do
    get admin_editing_block_path(kind: "page", id: @page.id, block_id: @inside.id, locale: "de")

    assert_select "#content_block_#{@inside.id}[data-editing-unit]", 1
    assert_select "#block-#{@inside.id}-panel", false
  end

  test "with mark=1 the card says who changed it, and never for the viewer's own change" do
    travel(1.minute) { as(users(:two), channel: :admin) { assert ContentBlocks::Save.call(@block, translations: { "en" => { caption: "x" } }).ok? } }
    users(:two).update!(name: "Dana Weiss")

    get admin_editing_block_path(kind: "page", id: @page.id, block_id: @block.id, mark: 1)
    assert_select "#content_block_#{@block.id} [data-editing-mark]", text: /Updated by Dana Weiss/

    get admin_editing_block_path(kind: "page", id: @page.id, block_id: @block.id)
    assert_select "[data-editing-mark]", false, "no mark without mark=1"

    get admin_editing_block_path(kind: "page", id: @page.id, block_id: @block.id, mark: 0)
    assert_select "[data-editing-mark]", false, "mark=0 is not mark=1"

    sign_in_as users(:two)
    get admin_editing_block_path(kind: "page", id: @page.id, block_id: @block.id, mark: 1)
    assert_select "[data-editing-mark]", false, "the changer is not told of their own change"
  end

  test "the record's form: the settings for a page, the form for a post, each a unit with the base its next save needs" do
    get admin_editing_record_path(kind: "page", id: @page.id)
    assert_select "#page-settings[data-editing-unit][data-editing-subject=record] input#page-base-updated-at[value=?]", @page.settings_changed_at.iso8601(6)

    post = create_post(title: "News", published: false)
    get admin_editing_record_path(kind: "post", id: post.id)
    assert_select "#post-form[data-editing-unit][data-editing-subject=record] input#post-base-updated-at[value=?]", post.updated_at.iso8601(6)
  end

  test "outside the read scope, in the trash, of another page and of an unknown kind every part is not found" do
    other = create_page(title: "Other", published: false)
    foreign = ContentBlocks::Save.call(ContentBlock.new(owner: other), attributes: { block_type: "rich_text" }).record
    get admin_editing_block_path(kind: "page", id: @page.id, block_id: foreign.id)
    assert_response :not_found

    get "/cs-studio/editing/media/1/record"
    assert_response :not_found

    post = create_post(title: "News")
    get "/cs-studio/editing/post/#{post.id}/blocks"
    assert_response :not_found

    sign_in_as @stranger
    [ admin_editing_blocks_path(kind: "page", id: @page.id), admin_editing_block_path(kind: "page", id: @page.id, block_id: @block.id),
      admin_editing_record_path(kind: "page", id: @page.id) ].each do |path|
      get path
      assert_response :not_found, path
    end
  end

  test "a block deleted since is gone, not missing" do
    id = @block.id
    assert ContentBlocks::Destroy.call(@block).ok?

    get admin_editing_block_path(kind: "page", id: @page.id, block_id: id)

    assert_response :gone
  end

  test "a reader gets the parts, view-only" do
    sign_in_as users(:reader)
    get admin_editing_blocks_path(kind: "page", id: @page.id)

    assert_response :ok
    assert_select "form[data-controller~='admin--saving--autosave']", false
  end

  test "the list costs the same statements for 3 blocks as for 30" do
    get admin_editing_blocks_path(kind: "page", id: @page.id) # the first request of a process also asks whether setup is complete
    ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "image", media_asset_id: create_media_asset.id })
    three = capture_sql { get admin_editing_blocks_path(kind: "page", id: @page.id) }.size
    27.times { ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }) }
    # An image with a library image, and a section with blocks in it: a query per image or per section would show.
    4.times do
      ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "image", media_asset_id: create_media_asset.id })
      section = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "section", settings: { "layout" => "two" } }).record
      2.times { |column| ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text", section_id: section.id, section_column: column + 1 }) }
    end
    thirty = capture_sql { get admin_editing_blocks_path(kind: "page", id: @page.id) }.size

    assert_equal three, thirty
  end

  # The browser swaps a fetched element for the page's own: they must be the
  # same element, byte for byte, not merely alike.
  test "every fragment is the element the editor's own page draws" do
    get admin_page_path(@page)
    editor = Nokogiri::HTML5.parse(response.body)
    html_of = lambda do |doc, selector|
      found = doc.css(selector).map { |node| node.to_html.gsub(/\s+/, " ").strip }
      assert_not_empty found, selector
      found
    end

    get admin_editing_blocks_path(kind: "page", id: @page.id)
    list = Nokogiri::HTML5.fragment(response.body)
    assert_equal editor.css("#content-blocks-list > *").map { |node| node.to_html.gsub(/\s+/, " ").strip }, list.children.select(&:element?).map { |node| node.to_html.gsub(/\s+/, " ").strip }

    get admin_editing_block_path(kind: "page", id: @page.id, block_id: @block.id)
    card = Nokogiri::HTML5.fragment(response.body)
    assert_equal html_of.(editor, "#content_block_#{@block.id}"), html_of.(card, "#content_block_#{@block.id}")

    get admin_editing_block_path(kind: "page", id: @page.id, block_id: @inside.id)
    parts = Nokogiri::HTML5.fragment(response.body)
    assert_equal html_of.(editor, "#content_block_#{@inside.id}"), html_of.(parts, "#content_block_#{@inside.id}")
    assert_equal html_of.(editor, "#block-#{@inside.id}-panel"), html_of.(parts, "#block-#{@inside.id}-panel")

    get admin_editing_record_path(kind: "page", id: @page.id)
    assert_equal html_of.(editor, "#page-settings"), html_of.(Nokogiri::HTML5.fragment(response.body), "#page-settings")

    post = create_post(title: "News", published: false)
    get admin_post_path(post)
    editor = Nokogiri::HTML5.parse(response.body)
    get admin_editing_record_path(kind: "post", id: post.id)
    fragment = Nokogiri::HTML5.fragment(response.body)
    assert_equal html_of.(editor, "#post-form"), html_of.(fragment, "#post-form")
  end

  A = "tab-aaaaaaaa".freeze
  B = "tab-bbbbbbbb".freeze

  def hold!(subject, user, tab) = Editing::Reservation.claim(subject:, record: @page, user:, tab:, now: Time.current)

  def tab(name) = { "X-Notes-Tab" => name }

  # Live-editing Review Focus 4 and handoff 1, 18: a held card is read-only for everyone but the tab that holds it.
  test "the fetched card is editable for the tab that holds it and read-only for everyone else, the holder's other tab included" do
    hold!(@block, users(:one), A)

    get admin_editing_block_path(kind: "page", id: @page.id, block_id: @block.id), headers: tab(A)
    assert_select "#content_block_#{@block.id} form[data-controller~='admin--saving--autosave']"
    assert_select "#content_block_#{@block.id} [data-editing-held]", false
    assert_select "#block-#{@block.id}-hold[data-editing-strip-slot]:empty"

    get admin_editing_block_path(kind: "page", id: @page.id, block_id: @block.id), headers: tab(B)
    assert_select "#content_block_#{@block.id}[data-editing-held=true]"
    assert_select "#content_block_#{@block.id} form[data-controller~='admin--saving--autosave']", false
    assert_select "#block-#{@block.id}-hold [data-editing-kind=held]", text: /editing this in another tab/

    sign_in_as users(:two)
    get admin_editing_block_path(kind: "page", id: @page.id, block_id: @block.id), headers: tab(B)
    assert_select "#content_block_#{@block.id}[data-editing-held=true]"
    assert_select "#content_block_#{@block.id} form[data-controller~='admin--saving--autosave']", false
    assert_select "#block-#{@block.id}-hold [data-editing-kind=held]", text: /is editing this block/
  end

  test "a block in a section, held by someone else: its panel is read-only with the strip, and its tile and the version say so" do
    free = nil
    get admin_editing_block_path(kind: "page", id: @page.id, block_id: @inside.id), headers: tab(B)
    free = Nokogiri::HTML5.fragment(response.body).css("[data-editing-version]").map { |node| node["data-editing-version"] }
    hold!(@inside, users(:two), A)

    get admin_editing_block_path(kind: "page", id: @page.id, block_id: @inside.id), headers: tab(B)
    assert_select "#block-#{@inside.id}-panel[hidden][data-editing-held=true] form[data-controller~='admin--saving--autosave']", false
    assert_select "#block-#{@inside.id}-panel #block-#{@inside.id}-hold [data-editing-kind=held]"
    assert_select "#block-#{@inside.id}-panel .admin-held"
    assert_select "#content_block_#{@inside.id}[data-editing-held=true]"
    held = Nokogiri::HTML5.fragment(response.body).css("[data-editing-version]").map { |node| node["data-editing-version"] }
    assert_not_equal free, held
  end

  test "the same fragment is the element the editor's own page draws when a block, a section's block and the settings are held" do
    freeze_time # the strip counts down to the hold's end: two requests are the same only at the same instant
    hold!(@block, users(:two), A)
    hold!(@inside, users(:two), A)
    hold!(@page, users(:two), A)
    get admin_page_path(@page), headers: tab(B)
    editor = Nokogiri::HTML5.parse(response.body)
    squash = ->(nodes) { nodes.map { |node| node.to_html.gsub(/\s+/, " ").strip } }

    get admin_editing_blocks_path(kind: "page", id: @page.id), headers: tab(B)
    assert_equal squash.(editor.css("#content-blocks-list > *")), squash.(Nokogiri::HTML5.fragment(response.body).children.select(&:element?))

    get admin_editing_block_path(kind: "page", id: @page.id, block_id: @block.id), headers: tab(B)
    assert_equal squash.(editor.css("#content_block_#{@block.id}")), squash.(Nokogiri::HTML5.fragment(response.body).css("#content_block_#{@block.id}"))

    get admin_editing_block_path(kind: "page", id: @page.id, block_id: @inside.id), headers: tab(B)
    parts = Nokogiri::HTML5.fragment(response.body)
    assert_equal squash.(editor.css("#content_block_#{@inside.id}")), squash.(parts.css("#content_block_#{@inside.id}"))
    assert_equal squash.(editor.css("#block-#{@inside.id}-panel")), squash.(parts.css("#block-#{@inside.id}-panel"))

    get admin_editing_record_path(kind: "page", id: @page.id), headers: tab(B)
    assert_equal squash.(editor.css("#page-settings")), squash.(Nokogiri::HTML5.fragment(response.body).css("#page-settings"))
    assert_select "#page-settings[data-editing-held=true] #page-hold [data-editing-kind=held]", text: /is editing the page settings/

    post = create_post(title: "News", published: false)
    Editing::Reservation.claim(subject: post, record: post, user: users(:two), tab: A, now: Time.current)
    get admin_post_path(post), headers: tab(B)
    page_editor = Nokogiri::HTML5.parse(response.body)
    get admin_editing_record_path(kind: "post", id: post.id), headers: tab(B)
    fragment = Nokogiri::HTML5.fragment(response.body)
    assert_equal squash.(page_editor.css("#post-form")), squash.(fragment.css("#post-form"))
    assert_equal squash.(page_editor.css("#editor-notice")), squash.(fragment.css("#editor-notice"))
  end

  test "a post's record answer carries the notice area, with the strip when someone else holds the post and empty when nobody does" do
    post = create_post(title: "News", published: false)

    get admin_editing_record_path(kind: "post", id: post.id), headers: tab(B)
    assert_select "#editor-notice:empty"

    Editing::Reservation.claim(subject: post, record: post, user: users(:two), tab: A, now: Time.current)
    get admin_editing_record_path(kind: "post", id: post.id), headers: tab(B)
    assert_select "#editor-notice [data-editing-kind=held]", text: /is editing this post/
    assert_select "#post-form[data-editing-held=true] .admin-held"
    assert_select "#post-form[data-controller~='admin--saving--autosave']", false
  end

  test "the list costs the same statements with a hold on every block, for 3 blocks as for 30" do
    get admin_editing_blocks_path(kind: "page", id: @page.id), headers: tab(B)
    hold!(@block, users(:two), A)
    hold!(@inside, users(:two), A)
    three = capture_sql { get admin_editing_blocks_path(kind: "page", id: @page.id), headers: tab(B) }.size
    27.times { |i| hold!(ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }).record, users(:two), "tab-#{i.to_s.rjust(8, "0")}") }
    thirty = capture_sql { get admin_editing_blocks_path(kind: "page", id: @page.id), headers: tab(B) }.size

    assert_equal three, thirty
  end

  test "the editor page reads the reservations in the same few statements for 3 blocks as for 30, some held" do
    get admin_page_path(@page), headers: tab(B)
    hold!(@block, users(:two), A)
    few = capture_sql { get admin_page_path(@page), headers: tab(B) }.grep(/edit_reservations/).size
    27.times do |i|
      block = ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }).record
      hold!(block, users(:two), "tab-#{i.to_s.rjust(8, "0")}") if i.even?
    end
    many = capture_sql { get admin_page_path(@page), headers: tab(B) }.grep(/edit_reservations/).size

    assert_equal few, many
    assert_operator few, :>, 0, "the page's reservations are read"
    assert_operator many, :<=, 3
  end

  test "the actions that draw cards (a duplicate) read the reservations in the same few statements, however many blocks" do
    hold!(@block, users(:two), A)
    post duplicate_admin_page_content_block_path(@page, @block), headers: tab(B)
    few = capture_sql { post duplicate_admin_page_content_block_path(@page, @block), headers: tab(B) }.grep(/edit_reservations/).size
    20.times { |i| hold!(ContentBlocks::Save.call(ContentBlock.new(owner: @page), attributes: { block_type: "rich_text" }).record, users(:two), "tab-#{i.to_s.rjust(8, "0")}") }
    many = capture_sql { post duplicate_admin_page_content_block_path(@page, @block), headers: tab(B) }.grep(/edit_reservations/).size

    assert_equal few, many
    assert_operator few, :>, 0, "the reservations are read once for the cards the action draws"
    assert_operator many, :<=, 3
  end

  test "the live region carries the addresses the scripts need, and nothing for blocks on a post" do
    get admin_page_path(@page)
    assert_select "#editing[data-controller='admin--editing--live'][data-live-part=waiting]" \
      "[data-admin--editing--live-kind-value=page][data-admin--editing--live-id-value='#{@page.id}']" \
      "[data-admin--editing--live-blocks-url-value='#{admin_editing_blocks_path(kind: "page", id: @page.id)}']" \
      "[data-admin--editing--live-block-url-value='/cs-studio/editing/page/#{@page.id}/blocks/:block_id']" \
      "[data-admin--editing--live-record-url-value='#{admin_editing_record_path(kind: "page", id: @page.id)}']" \
      "[data-admin--editing--live-notice-value='6000']"
    assert_select "#editing #page-settings"
    assert_select "#editing #content-blocks-list"

    post = create_post(title: "News", published: false)
    get admin_post_path(post)
    assert_select "#editing[data-admin--editing--live-kind-value=post] #post-form"
    assert_select "#editing[data-admin--editing--live-blocks-url-value]", false
  end
end
