require "test_helper"

class Admin::NotesDrawerTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @page = create_page(title: "Pricing")
    @block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    @post = create_post(title: "Hello")
    as(users(:two)) { [ @page, @block, @post ].each { |subject| Notes::Start.call(subject, body: "A note") } }
  end

  # The notes frame holds forms of its own (the composer, Resolve), and forms
  # can't nest: inside an editor form its fields would also be the autosave's.
  def assert_drawer_outside_every_form
    assert_select "form aside#notes-drawer", count: 0
    assert_select "form turbo-frame#notes", count: 0
    assert_select "[data-controller~='admin--autosave'] turbo-frame#notes", count: 0
    assert_select "turbo-frame#content aside#notes-drawer turbo-frame#notes", count: 1
  end

  test "the page editor has the Notes button with the open count before Preview, and the drawer outside every form" do
    sign_in_as(users(:two))

    get "/cs-studio/pages/#{@page.id}"

    assert_select "header.admin-editor-header button#notes-open[aria-controls=notes-drawer] #notes-open-count", text: "2"
    assert_operator response.body.index('id="notes-open"'), :<, response.body.index(">Preview<")
    # The header's shared secondary style, as Preview beside it (the handoff's
    # decision 2): 16px text, `px-4 py-2`, a 16px icon, the count in 12px mono.
    assert_select "button#notes-open[class~='px-4'][class~='py-2'][class~='border-line-strong'][class~='rounded-cs'] svg[class~='size-4']"
    assert_select "button#notes-open[class*='text-[13px]'], button#notes-open[class~='text-sm']", count: 0
    assert_select "button#notes-open[class~='aria-pressed:bg-sunken'][class~='aria-pressed:border-ink']"
    assert_select "#notes-open-count[class~='font-cs-mono'][class~='text-xs'][class~='text-dim'][class~='data-[unread]:bg-accent']"
    assert_select "aside#notes-drawer[hidden][data-admin--notes-target=drawer][data-key='Page-#{@page.id}'][data-src='/cs-studio/notes/page/#{@page.id}']" do
      assert_select "turbo-frame#notes[data-admin--notes-target=frame]"
      assert_select "button", text: "Back to Pricing"
      assert_select "form", count: 0
    end
    assert_drawer_outside_every_form
    assert_select "span#notes-counts[data-counts]"
    assert_select "body[data-controller~='admin--notes']"
    # One element answers to the header button's id (the plan's stable ids).
    assert_select "#notes-open", count: 1
  end

  test "the post editor has the same button and drawer; ?notes=open and a thread travel to the drawer" do
    thread = Notes::Thread.find_by!(subject: @post)
    sign_in_as(users(:two))

    get "/cs-studio/posts/#{@post.id}", params: { notes: "open", thread: thread.id }

    assert_select "button#notes-open #notes-open-count", text: "1"
    assert_select "aside#notes-drawer[data-open-on-load=true][data-thread='#{thread.id}'][data-src='/cs-studio/notes/post/#{@post.id}']" do
      assert_select "button", text: "Back to Hello"
    end
    assert_drawer_outside_every_form
  end

  # The handoff's decision 9: the stylesheet shows it from 1280px while the
  # notes column has folded the tree away.
  test "the page editor's breadcrumb row starts with the tree drawer's Pages button, and the post editor has none" do
    sign_in_as(users(:two))

    get "/cs-studio/pages/#{@page.id}"
    assert_select "header.admin-editor-header button.admin-editor-header__tree[aria-controls=tree-column][aria-expanded=false][aria-label='Open page tree'][data-action='admin--shell--drawer#toggle'][data-admin--shell--drawer-name-param=tree][data-admin--shell--drawer-target=trigger]", text: "Pages ▾", count: 1
    assert_select "header.admin-editor-header button.admin-editor-header__tree + nav[aria-label=Breadcrumb]"

    get "/cs-studio/posts/#{@post.id}"
    assert_select ".admin-editor-header__tree", count: 0
  end

  test "a thread that is not a number does not travel, and without ?notes=open the drawer stays shut" do
    sign_in_as(users(:two))

    get "/cs-studio/pages/#{@page.id}", params: { thread: "3/../../x" }

    assert_select "aside#notes-drawer[data-open-on-load=false]"
    assert_select "aside#notes-drawer[data-thread]", count: 0
  end

  test "without open notes the button is the word alone" do
    Notes::Thread.where(container: @post).each { |thread| as(users(:two)) { Notes::Resolve.call(thread) } }
    sign_in_as(users(:two))

    get "/cs-studio/posts/#{@post.id}"

    assert_select "button#notes-open[aria-label='Notes, 0 open'][aria-pressed=false]" do
      assert_select "span:not([hidden])", text: "Notes", count: 1
      assert_select "#notes-open-count[hidden]"
    end
    # Nor does the drawer's own header say "0 open".
    assert_select "aside#notes-drawer header [data-admin--notes-target=total][hidden]"
  end

  test "a view-only reader gets the button and the drawer" do
    sign_in_as(users(:reader))

    get "/cs-studio/pages/#{@page.id}"

    assert_select "button#notes-open"
    assert_select "aside#notes-drawer"
  end

  test "the editor costs the same statements whatever the number of threads" do
    sign_in_as(users(:two))
    get "/cs-studio/pages/#{@page.id}"
    few = capture_sql { get "/cs-studio/pages/#{@page.id}" }.size
    as(users(:reader)) { 9.times { Notes::Start.call(@block, body: "More") } }
    get "/cs-studio/pages/#{@page.id}"

    assert_equal few, capture_sql { get "/cs-studio/pages/#{@page.id}" }.size
  end
end
