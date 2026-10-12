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
    # <dialog>'s content as visible. The Publish changes form is in the header
    # for whoever may publish and shown by a mark (CSS), so no mark is no primary button.
    assert_no_selector "header [data-publish-changes-offered]", visible: :all
    assert_selector "[role=status]", text: "This page is live. Changes are published with “Publish changes…”."
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

  def edit_title(record, title = "Edited")
    assert as_owner { Pages::Save.call(record, translations: { "en" => { title: title } }) }.ok? if record.is_a?(Page)
    assert as_owner { Posts::Save.call(record, translations: { "en" => { title: title } }) }.ok? if record.is_a?(Post)
    record.reload
  end

  test "a live record with unpublished changes shows the chip and Publish changes; without changes neither, and both elements are there, empty" do
    live = create_page(title: "About", published: true)
    render_header(live)
    assert_selector "header #publishing-chip", visible: :all
    assert_selector "header #publishing-actions", visible: :all
    assert_no_selector "header #publishing-chip [data-unpublished-changes]"
    assert_no_selector "header [data-publish-changes-offered]", visible: :all # the form is drawn once for whoever may publish, and shown by this mark

    render_header(edit_title(live))
    assert_selector "header #publishing-chip [data-unpublished-changes]", text: "Unpublished changes"
    assert_selector "header #publishing-actions button[data-admin--ui--dialog-id-param='publish-changes-page-#{live.id}']", text: "Publish changes…"
    assert_selector "header #publishing-chip [data-publish-changes-offered]", visible: :all
    assert_selector "header #publishing-chip [data-discard-changes-offered]", visible: :all
  end

  test "a scheduled record with unpublished changes offers them too, and a draft shows neither the chip nor the button, whatever mark it kept" do
    post = create_post(title: "Later", published: false)
    as_owner { Posts::Save.call(post, attributes: { published_at: 3.days.from_now }) }
    render_header(post.reload)
    assert_no_selector "header [data-publish-changes-offered]", visible: :all

    render_header(edit_title(post.reload))
    assert_selector "header [data-unpublished-changes]"
    assert_selector "header [data-publish-changes-offered]", visible: :all

    draft = create_page(title: "Draft", published: false)
    draft.update_columns(unpublished_changes_at: Time.current) # version: none (a test gives a draft a stale mark) # changes: none (a test gives a draft a stale mark)
    render_header(draft)
    assert_no_selector "header [data-unpublished-changes]"
    assert_no_selector "header #publishing-chip", visible: :all
    assert_no_selector "header button", text: "Publish changes", visible: :all
  end

  test "a live record with a change scheduled offers Publish changes with or without edits since, because its time can be changed" do
    live = create_page(title: "About")
    assert as_owner { Pages::Save.call(live, translations: { "en" => { title: "Edited" } }) }.ok?
    assert as_owner { Publishing::PublishChanges.call(live.reload, at: 2.days.from_now) }.ok?
    assert_not live.reload.unpublished_changes?

    render_header(live)

    assert_selector "header #publishing-actions button[data-action='admin--ui--dialog#open'][data-admin--ui--dialog-id-param='publish-changes-page-#{live.id}']", text: "Publish changes…"
    assert_selector "header #publishing-chip [data-publish-changes-offered]", visible: :all
    assert_selector "header #publishing-chip [data-discard-changes-offered]", visible: :all
    assert_no_selector "header [data-unpublished-changes]"
  end

  # -- Task 7: the dialogs ---------------------------------------------------------

  test "the Publish changes control opens the dialog and is not a form" do
    live = edit_title(create_page(title: "About"))
    render_header(live)

    assert_selector "header #publishing-actions button[type=button][data-admin--ui--dialog-id-param='publish-changes-page-#{live.id}']", text: "Publish changes…"
    assert_selector "dialog#publish-changes-page-#{live.id} form[action='/cs-studio/publishing/page/#{live.id}/publish']", visible: :all
  end

  test "no form in the header publishes without the dialog" do
    render_header(edit_title(create_page(title: "About")))

    assert_no_selector "#publishing-actions form", visible: :all
    assert_no_selector "header form[action*='/publishing/']", visible: :all
  end

  test "Discard changes… is offered with it to someone who may change the record, opens its own dialog, and stands before Publish changes…" do
    live = edit_title(create_page(title: "About"))
    render_header(live)

    assert_selector "header #publishing-actions button[type=button][data-admin--ui--dialog-id-param='discard-changes-page-#{live.id}']", text: "Discard changes…"
    assert_equal [ "Discard changes…", "Publish changes…" ], page.all("header #publishing-actions button", visible: :all).map { |button| button.text(:all).strip }
    assert_selector "dialog#discard-changes-page-#{live.id}[data-destructive] form[action='/cs-studio/publishing/page/#{live.id}/discard']", visible: :all
  end

  test "the buttons and the dialogs are drawn for a live record with nothing to publish too, without their marks: the first save's answer shows them" do
    live = create_page(title: "About")
    render_header(live)

    assert_selector "header #publishing-actions button", text: "Publish changes…", visible: :all
    assert_selector "header #publishing-actions button", text: "Discard changes…", visible: :all
    wrappers = page.all("header #publishing-actions > span", visible: :all).map { |span| span[:class] }
    assert_equal [ "hidden group-has-[[data-discard-changes-offered]]/publishing:contents", "hidden group-has-[[data-publish-changes-offered]]/publishing:contents" ], wrappers
    assert_no_selector "header [data-publish-changes-offered]", visible: :all
    assert_no_selector "header [data-discard-changes-offered]", visible: :all
    assert_selector "dialog#publish-changes-page-#{live.id}", visible: :all
    assert_selector "dialog#discard-changes-page-#{live.id}", visible: :all
    assert_includes page.find("header.admin-editor-header")[:class].split, "group/publishing"
  end

  test "a draft has neither the dialogs nor the buttons" do
    draft = create_page(title: "Draft", published: false)
    render_header(draft)

    assert_no_selector "dialog[id^=publish-changes-]", visible: :all
    assert_no_selector "dialog[id^=discard-changes-]", visible: :all
    assert_no_selector "dialog[id^=cancel-scheduled-change-]", visible: :all
  end

  test "changes that are scheduled are named with their time, and Cancel scheduled change is in the menu with its confirmation" do
    live = create_page(title: "About")
    assert as_owner { Pages::Save.call(live, translations: { "en" => { title: "Edited" } }) }.ok?
    assert as_owner { Publishing::PublishChanges.call(live.reload, at: Time.zone.local(2031, 10, 12, 9)) }.ok?

    render_header(live.reload)

    assert_selector "header #publishing-chip [data-change-scheduled]", text: "Changes scheduled for 12 Oct 2031, 09:00"
    assert_selector "[role=menu] button[data-admin--ui--dialog-id-param='cancel-scheduled-change-page-#{live.id}']", text: "Cancel scheduled change", visible: :all
    assert_selector "dialog#cancel-scheduled-change-page-#{live.id} form[action='/cs-studio/publishing/page/#{live.id}/cancel_scheduled_change']", visible: :all
    items = page.all("[role=menu] a, [role=menu] button", visible: :all).map { |item| item.text(:all).strip }
    assert_equal [ "Cancel scheduled change", "Unpublish" ], items[items.index("Cancel scheduled change"), 2]
  end

  test "with no change scheduled there is no such item, no such dialog and no such line" do
    live = edit_title(create_page(title: "About"))
    render_header(live)

    assert_no_selector "[role=menu] button", text: "Cancel scheduled change", visible: :all
    assert_no_selector "dialog[id^=cancel-scheduled-change-]", visible: :all
    assert_no_selector "[data-change-scheduled]"
  end

  test "someone who may read but not change the record gets no button, no dialog and no menu item of these" do
    live = create_page(title: "About")
    assert as_owner { Pages::Save.call(live, translations: { "en" => { title: "Edited" } }) }.ok?
    assert as_owner { Publishing::PublishChanges.call(live.reload, at: 2.days.from_now) }.ok?
    assert as_owner { Pages::Save.call(live.reload, translations: { "en" => { title: "Edited again" } }) }.ok?

    render_header(live.reload, actor: users(:reader))

    assert_selector "header [data-unpublished-changes]"
    assert_selector "header [data-change-scheduled]"
    assert_no_selector "button", text: /Publish changes|Discard changes|Cancel scheduled change/, visible: :all
    assert_no_selector "dialog[id^=publish-changes-], dialog[id^=discard-changes-], dialog[id^=cancel-scheduled-change-]", visible: :all
    assert_no_selector "[data-publish-changes-offered], [data-discard-changes-offered]", visible: :all
  end

  test "someone who may not publish sees the chip and no button" do
    post = edit_title(create_post(title: "Read me"))

    render_header(post, actor: users(:reader))

    assert_selector "header [data-unpublished-changes]"
    assert_no_selector "header button", text: "Publish changes", visible: :all
    assert_no_selector "header button", text: "Discard changes", visible: :all
  end

  test "a live page that has no address says so, and one that has an address, a draft and an unlisted post do not" do
    page = create_page(title: "About")
    render_header(page)
    assert_no_selector "header [data-no-address]"

    PublicPath.where(record: page).delete_all # version: none (a test takes a live page's address away) # changes: none (a test removes derived rows)
    render_header(page.reload)
    assert_selector "header #publishing-chip [data-no-address]", text: "No address"

    draft = create_page(title: "Draft", published: false)
    PublicPath.where(record: draft).delete_all # version: none (a test takes a draft's address away) # changes: none (a test removes derived rows)
    render_header(draft)
    assert_no_selector "header [data-no-address]"

    render_header(create_post(title: "Nobody lists me"))
    assert_no_selector "header [data-no-address]", text: "No address"
  end

  test "a viewer who can only read sees View only and nothing that writes" do
    post = create_post(title: "Read me")
    render_header(post, actor: users(:reader))
    assert_selector "[data-view-only]", text: "View only"
    assert_no_selector "button", text: /Publish|Unpublish|Schedule|Move to trash/, visible: :all
  end

  # Task 19's f2: the "changes are published with Publish changes" hint is about
  # the viewer's own edits.
  test "a view-only viewer of a live record is not told their changes go live" do
    post = create_post(title: "Read me", published: true)
    render_header(post, actor: users(:reader))
    assert_no_text "Changes are published with"
    assert_selector "[data-view-only-hint]"

    render_header(post)
    assert_text "Changes are published with “Publish changes…”."
  end

  test "a post shows its type and, unlisted, says so" do
    post = create_post(title: "Loose")
    render_header(post)
    assert_selector ".admin-type-dot"
    assert_text "Not listed on any page yet — add a post list block for this type"
  end

  test "a scheduled page's hint says what was scheduled goes live at its time" do
    page = create_page(title: "Later", published: false)
    assert as_owner { Pages::Save.call(page, attributes: { published_at: 3.days.from_now }) }.ok?
    render_header(page.reload)

    assert_selector "[role=status]", text: "This page is scheduled. What was scheduled goes live at its time; later changes are published with “Publish changes…”."
    assert_selector "p#page-save-status[data-live]", visible: :all

    post = create_post(title: "Later post", published: false)
    assert as_owner { Posts::Save.call(post, attributes: { published_at: 3.days.from_now }) }.ok?
    render_header(post.reload)
    assert_selector "[role=status]", text: "This post is scheduled. What was scheduled goes live at its time"
  end

  test "a draft has no such hint, and its save line is the plain one" do
    render_header(create_page(title: "Draft", published: false))

    assert_no_text "Changes are published with"
    assert_no_text "later changes are published"
    assert_no_selector "p#page-save-status[data-live]", visible: :all
  end

  test "a post without an address whose list block waits in a live page's unpublished rows says so, naming the page to someone who may read it" do
    blog = create_page(title: "Journal page")
    post = create_post(title: "Loose")
    assert as_owner { ContentBlocks::Save.call(ContentBlock.new(owner: blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }) }.ok?
    assert_nil post.reload.full_path("en"), "the list block is not published, so the post has no address"

    render_header(post)
    assert_selector "[data-waiting-lister]", text: "Not listed on the site yet: the page “Journal page” lists this post, and its changes are not published."
    assert_no_text "add a post list block for this type"

    group = AccessControl::Group.create!(name: "Posts only")
    AccessControl::Grant.create!(group: group, permission: "posts.read", scope: {})
    reader = User.create!(email_address: "posts-only@example.com", password: "password12345")
    AccessControl::Membership.create!(user: reader, group: group)
    render_header(post, actor: reader)
    assert_selector "[data-waiting-lister]", text: "Not listed on the site yet: a page lists this post, and its changes are not published."
    assert_no_text "Journal page"

    as_owner { publish_changes(blog) }
    render_header(post.reload)
    assert_no_selector "[data-waiting-lister]"
    assert_no_text "Not listed"
  end

  test "a list block in a draft page's rows, in a trashed page's, or for another type is no such line" do
    post = create_post(title: "Loose")
    draft = create_page(title: "Draft list", published: false)
    assert as_owner { ContentBlocks::Save.call(ContentBlock.new(owner: draft), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }) }.ok?
    other = create_page(title: "Other type")
    assert as_owner { ContentBlocks::Save.call(ContentBlock.new(owner: other), attributes: { block_type: "post_list", settings: { "content_type" => "now_update" } }) }.ok?
    trashed = create_page(title: "Trashed list")
    assert as_owner { ContentBlocks::Save.call(ContentBlock.new(owner: trashed), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }) }.ok?
    assert as_owner { Trash::Move.call(trashed.reload) }.ok?

    render_header(post.reload)

    if post.full_path("en").nil?
      assert_no_selector "[data-waiting-lister]"
      assert_text "Not listed on any page yet — add a post list block for this type"
    else
      assert_equal "/draft-list/loose", post.full_path("en"), "a draft page lists what its rows list, so the post has a would-be address there"
      assert_no_selector "[data-waiting-lister]"
    end
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
    with_site_address("https://www.my-site.test") do
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

  def without_public_host(&)
    with_site_address(nil, &)
  end
end
