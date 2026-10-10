require "test_helper"

# The one editor header for pages and posts (design pass round 2, handoff
# §4.1/§9 B15): breadcrumb, title and chips, the public path, language tabs,
# ONE primary action and a ⋯ menu -- no longer five equal buttons.
class Admin::EditorScreen::HeaderComponentTest < ViewComponent::TestCase
  include ContentHelper

  def render_header(record, locale: "en", actor: users(:one))
    as(actor, channel: :admin) { render_inline(Admin::EditorScreen::HeaderComponent.new(record: record, locale: locale)) }
  end

  test "a draft: breadcrumb, title, Draft chip, Preview and one primary Publish, the rest in the menu" do
    page = create_page(title: "About", published: false)
    render_header(page)
    assert_selector "header.admin-editor-header[data-record-type=page][data-record-id='#{page.id}']"
    assert_selector "nav[aria-label='Breadcrumb']", text: "Pages"
    assert_selector "h1", text: "About"
    assert_selector ".admin-status-chip[data-status=draft]"
    assert_selector "a", text: "Preview"
    assert_selector "button.bg-accent", text: "Publish", count: 1
    assert_selector "[role=menu] a", text: "Activity", visible: :all
    assert_selector "[role=menu] button", text: "Schedule…", visible: :all
    assert_selector "[role=menu] button", text: "Move to trash", visible: :all
    assert_no_selector "[role=menu] button", text: "Unpublish", visible: :all
  end

  test "the Pages crumb links on a subpage but is plain text on Home, which /pages would reopen" do
    render_header(create_page(title: "About"))
    assert_selector "nav[aria-label='Breadcrumb'] a", text: "Pages"
    render_header(root_page)
    assert_no_selector "nav[aria-label='Breadcrumb'] a", text: "Pages"
    assert_selector "nav[aria-label='Breadcrumb']", text: "Pages"
  end

  test "a live record: no primary button, the live hint, Unpublish in the menu, View on site" do
    page = create_page(title: "About", published: true)
    render_header(page)
    # Scoped to the header: the Unpublish confirm dialog is a sibling AFTER it
    # and its confirm button is (rightly) primary; rack_test treats a closed
    # <dialog>'s content as visible.
    assert_no_selector "header button.bg-accent"
    assert_selector "[role=status]", text: "This page is live. Changes appear on the site as soon as they’re saved."
    assert_selector "[role=menu] button", text: "Unpublish", visible: :all
    assert_selector "a[href='/about']", text: "View on site"
  end

  test "a scheduled record: Publish now primary and Edit schedule secondary" do
    post = create_post(title: "Later", published: false)
    as_owner { Posts::Save.call(post, attributes: { published_at: 3.days.from_now }) }
    render_header(post.reload)
    assert_selector "button.bg-accent", text: "Publish now"
    assert_selector "button", text: "Edit schedule"
    assert_selector ".admin-status-chip[data-status=scheduled]"
  end

  test "Schedule… and Edit schedule open the Schedule dialog, rendered after the header" do
    page_record = create_page(title: "About", published: false)
    render_header(page_record)
    assert_selector "[role=menu] button[data-action='admin--ui--dialog#open'][data-admin--ui--dialog-id-param='schedule-page-#{page_record.id}']", text: "Schedule…", visible: :all
    assert_selector "dialog#schedule-page-#{page_record.id}", visible: :all

    post = create_post(title: "Later", published: false)
    as_owner { Posts::Save.call(post, attributes: { published_at: 3.days.from_now }) }
    render_header(post.reload)
    assert_selector "button[data-admin--ui--dialog-id-param='schedule-post-#{post.id}']", text: "Edit schedule"
    assert_selector "dialog#schedule-post-#{post.id} button", text: "Remove schedule", visible: :all
  end

  test "a live record has no Schedule dialog" do
    render_header(create_page(title: "About", published: true))
    assert_no_selector "dialog[id^=schedule-]", visible: :all
  end

  test "the menu's last item is Move to trash, after a divider; the homepage has it disabled with the reason" do
    render_header(root_page)
    items = page.all("[role=menu] a, [role=menu] button", visible: :all).map { |i| i.text(:all).strip }
    assert_equal "Move to trash", items.last
    assert_selector "[role=menu] button[disabled][title='The homepage can’t be deleted']", text: "Move to trash", visible: :all
    assert_no_selector "dialog#delete-page-#{root_page.id}", visible: :all
  end

  test "a divider separates the destructive item from the rest" do
    render_header(create_page(title: "About", published: false))
    assert_selector "[role=menu] [role=separator]", visible: :all
  end

  test "a viewer who can only read sees View only and nothing that writes" do
    post = create_post(title: "Read me")
    render_header(post, actor: users(:reader))
    assert_selector "[data-view-only]", text: "View only"
    assert_no_selector "button", text: /Publish|Unpublish|Schedule|Move to trash/, visible: :all
  end

  # Task 19's f2: the "changes appear as soon as they're saved" hint is about
  # the viewer's own edits.
  test "a view-only viewer of a live record is not told their changes go live" do
    post = create_post(title: "Read me", published: true)
    render_header(post, actor: users(:reader))
    assert_no_text "Changes appear on the site"
    assert_selector "[data-view-only-hint]"

    render_header(post)
    assert_text "Changes appear on the site as soon as they’re saved."
  end

  test "a post shows its type and, unlisted, says so" do
    post = create_post(title: "Loose")
    render_header(post)
    assert_selector ".admin-type-dot"
    assert_text "Not listed on any page yet — add a post list block for this type"
  end

  test "the dialog ids the later tasks and the tests rely on" do
    page_record = create_page(title: "About", published: false)
    post_record = create_post(title: "Loose")
    page_header = Admin::EditorScreen::HeaderComponent.new(record: page_record, locale: "en")
    post_header = Admin::EditorScreen::HeaderComponent.new(record: post_record, locale: "en")

    assert_equal "schedule-page-#{page_record.id}", page_header.schedule_dialog_id
    assert_equal "delete-page-#{page_record.id}", page_header.delete_dialog_id
    assert_equal "page-save-status", page_header.save_status_id
    assert_equal "schedule-post-#{post_record.id}", post_header.schedule_dialog_id
    assert_equal "delete-post-#{post_record.id}", post_header.delete_dialog_id
    assert_equal "post-save-status", post_header.save_status_id
  end

  test "breadcrumb: a page's ancestors link when readable, a post's type links to the filtered list" do
    section = create_page(title: "Section")
    child = create_page(title: "Child", parent: section)
    render_header(child)
    assert_selector "nav[aria-label='Breadcrumb'] a", text: "Section"

    render_header(create_post(title: "Hello"))
    assert_selector "nav[aria-label='Breadcrumb']", text: "Posts"
    assert_selector "nav[aria-label='Breadcrumb'] a[href*='type=blog']"
  end

  test "Unpublish opens a confirm dialog that names the subpages when there are some" do
    parent = create_page(title: "Section")
    create_page(title: "Child", parent: parent)
    render_header(parent.reload)
    assert_selector "dialog#unpublish-page-#{parent.id}", visible: :all
    assert_selector "dialog#unpublish-page-#{parent.id} h2", text: "Unpublish this page?", visible: :all
    assert_selector "dialog#unpublish-page-#{parent.id}", text: "It will show “not found” on the site. Subpages also show not found.", visible: :all
    assert_selector "dialog#unpublish-page-#{parent.id} form[data-turbo-frame='_top'][action='/cs-studio/pages/#{parent.id}/unpublish']", visible: :all
  end

  test "Move to trash names the subpage count; a leaf page has no subpage sentence" do
    parent = create_page(title: "Section")
    create_page(title: "Child one", parent: parent)
    create_page(title: "Child two", parent: parent)
    render_header(parent.reload)
    assert_selector "[role=menu] button", text: "Move to trash", visible: :all
    assert_no_selector "[role=menu] button[disabled]", text: "Move to trash", visible: :all
    assert_text :all, "This also moves 2 subpages to the trash."

    render_header(create_page(title: "Leaf"))
    assert_no_text :all, "subpage"
  end

  test "publishing forms leave the content frame, for posts as for pages" do
    page_record = create_page(title: "Draft", published: false)
    render_header(page_record)
    assert_selector "form[data-turbo-frame='_top'][action='/cs-studio/pages/#{page_record.id}/publish']"

    post_record = create_post(title: "Draft post", published: false)
    render_header(post_record)
    assert_selector "form[data-turbo-frame='_top'][action='/cs-studio/posts/#{post_record.id}/publish']"
  end

  # "View on site" used to be the absolute URL on the configured public
  # host -- on a local checkout (no PUBLIC_HOST) that was the placeholder
  # www.example.com, a dead link. The site is served by this same app, so
  # the link is the path; only "Copy" needs an absolute address, and it
  # falls back to the request's own origin when no host is configured.
  test "View on site is a same-origin path, and Copy uses the request's origin when no public host is configured" do
    without_public_host do
      page_record = create_page(title: "About", published: true)

      render_header(page_record.reload)

      assert_selector "a[href='/about']", text: "View on site"
      assert_selector "button[data-admin--ui--clipboard-url-value='http://test.host/about']", text: "Copy"
      assert_no_text "example.com"
    end
  end

  test "Copy uses the configured public host when there is one; View on site stays same-origin" do
    without_public_host do
      ENV["PUBLIC_HOST"] = "https://www.my-site.test"
      page_record = create_page(title: "About", published: true)

      render_header(page_record.reload)

      assert_selector "a[href='/about']", text: "View on site"
      assert_selector "button[data-admin--ui--clipboard-url-value='https://www.my-site.test/about']"
    end
  end

  class PeopleProbeComponent < ViewComponent::Base
    def initialize(**) = nil

    def call = tag.b("people", data: { slot_probe: "people" })
  end

  class ActionsProbeComponent < ViewComponent::Base
    cattr_accessor :seen

    def initialize(record:, viewer:, data: nil, **context) = (self.class.seen = [ record, viewer, data, context ])

    def call = tag.b("actions", data: { slot_probe: "actions" })
  end

  test "the people slot is the first thing of the action row and the actions slot stands between the save status and Preview" do
    page = create_page(title: "About", published: false)

    Admin::Slots.with("editor.header.people" => [ PeopleProbeComponent ], "editor.header.actions" => [ ActionsProbeComponent ]) { render_header(page) }

    html = rendered_content
    order = [ 'data-slot-probe="people"', 'id="page-save-status"', 'data-slot-probe="actions"', ">Preview<" ].map { |needle| html.index(needle) }
    assert_not_includes order, nil
    assert_equal order.sort, order
  end

  test "the slots are handed the record, the viewer, no data and the host's context, and an empty slot draws nothing" do
    page = create_page(title: "About", published: false)

    Admin::Slots.with("editor.header.people" => [], "editor.header.actions" => [ ActionsProbeComponent ]) do
      as(users(:one), channel: :admin) { render_inline(Admin::EditorScreen::HeaderComponent.new(record: page, locale: "de", url_options: { locale: "de" }, slot_context: { extra: 1 })) }
    end

    assert_equal [ page, users(:one), nil, { locale: "de", url_options: { locale: "de" }, extra: 1 } ], ActionsProbeComponent.seen
    assert_no_selector "[data-slot-probe=people]"
  end

  private

  def without_public_host
    saved = ENV.to_h.slice("PUBLIC_HOST", "SITEMAP_HOST")
    ENV.delete("PUBLIC_HOST")
    ENV.delete("SITEMAP_HOST")
    yield
  ensure
    ENV.delete("PUBLIC_HOST")
    ENV.delete("SITEMAP_HOST")
    saved.each { |key, value| ENV[key] = value }
  end
end
