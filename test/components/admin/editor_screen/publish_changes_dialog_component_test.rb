require "test_helper"

# The dialogs of a published or scheduled record's header (drafts spec §3).
class Admin::EditorScreen::PublishChangesDialogComponentTest < ViewComponent::TestCase
  include ContentHelper

  setup do
    @live = create_page(title: "Pricing")
    assert Pages::Save.call(@live, translations: { "en" => { title: "Pricing, edited" } }).ok?
  end

  def dialogs(record = @live, actor: users(:one), **options)
    as(actor) { render_inline Admin::EditorScreen::PublishChangesDialogComponent.new(record: record.reload, **options) }
  end

  def publish_dialog = "dialog#publish-changes-page-#{@live.id}"

  def texts(selector) = page.all(selector, visible: :all).map { |node| node.text(:all).strip }

  test "the dialog holds an empty overview that a POST through the write queue fills, and a form with Now and At a time" do
    dialogs

    assert_selector "#{publish_dialog}[data-dialog-width=form] h2", text: "Publish changes", visible: :all
    body = "#{publish_dialog} [data-controller='admin--editor--publish-dialog'][data-admin--editor--publish-dialog-url-value='/cs-studio/publishing/page/#{@live.id}/changes']"
    assert_selector "#{body}[data-action='admin--ui--dialog:opening@window->admin--editor--publish-dialog#opening']", visible: :all
    assert_selector "#{body} #publishing-changes[data-admin--editor--publish-dialog-target=overview]:empty", visible: :all
    assert_selector "#{body} [data-admin--editor--publish-dialog-target=loading]", text: "Reading what will change…", visible: :all
    assert_selector "#{body} [data-admin--editor--publish-dialog-target=failed][hidden]", visible: :all
    assert_no_selector "turbo-frame", visible: :all
    assert_selector "#{body} form[action='/cs-studio/publishing/page/#{@live.id}/publish'][novalidate]", visible: :all
    assert_selector "#{publish_dialog} legend", text: "When", visible: :all
    assert_equal [ "Now", "At a time" ], texts("#{publish_dialog} fieldset label:not([hidden])")
    # "At the scheduled time" is in the form from the start, hidden and unworded: the script shows it when the server says a change is scheduled.
    assert_selector "#{publish_dialog} fieldset label[hidden][data-admin--editor--publish-dialog-target=keptRow] input[type=radio][value=kept]:not([checked])", visible: :all
    assert_selector "#{publish_dialog} form input[type=hidden][name=pending][value='']", visible: :all
    assert_selector "#{publish_dialog} input[type=radio][name=when][value=now][checked]", visible: :all
    assert_selector "#{publish_dialog} input[type=datetime-local][name=published_at][aria-label='Date and time']", visible: :all
    assert_selector "#{publish_dialog} fieldset p", text: "the site’s time zone.", visible: :all
    assert_equal [ "Cancel", "Publish changes" ], texts("#{publish_dialog} footer button")
    assert_selector "#{publish_dialog} footer button[type=submit][form='publish-changes-page-#{@live.id}-form']", text: "Publish changes", visible: :all
    assert_no_selector "#{publish_dialog}[data-admin--ui--dialog-open-on-load]", visible: :all
  end

  test "a time typed or picked chooses At a time" do
    dialogs

    assert_selector "#{publish_dialog} input[type=datetime-local][data-action='input->admin--editor--publish-dialog#choseTime change->admin--editor--publish-dialog#choseTime']", visible: :all
    assert_selector "#{publish_dialog} input[type=radio][value=at][data-admin--editor--publish-dialog-target=at]", visible: :all
  end

  test "with changes scheduled, 'At the scheduled time' is offered and chosen, and the field holds that time" do
    publish_changes(@live, at: Time.zone.local(2031, 10, 12, 9))
    dialogs

    assert_equal [ "At the scheduled time (12 Oct 2031, 09:00)", "Now", "At a time" ], texts("#{publish_dialog} fieldset label:not([hidden])")
    assert_selector "#{publish_dialog} form input[type=hidden][name=pending][value='#{Publishing.pending(@live).id}']", visible: :all
    assert_selector "#{publish_dialog} input[type=radio][name=when][value=kept][checked]", visible: :all
    assert_selector "#{publish_dialog} input[type=radio][name=when][checked]", count: 1, visible: :all
    assert_selector "#{publish_dialog} input[name=published_at][value='2031-10-12T09:00']", visible: :all
  end

  test "the discard dialog asks once, with a destructive confirm, and its form posts to discard" do
    dialogs

    discard = "dialog#discard-changes-page-#{@live.id}"
    assert_selector "#{discard}[data-destructive][data-dialog-width=confirm] h2", text: "Discard the unpublished changes?", visible: :all
    assert_selector discard, text: "This page goes back to what is published. Blocks added since are deleted with their notes; blocks deleted since come back without theirs.", visible: :all
    assert_selector "#{discard} form[action='/cs-studio/publishing/page/#{@live.id}/discard'][method=post] button[type=submit]", text: "Discard changes", visible: :all
    assert_selector "#{discard} footer button[autofocus]", text: "Cancel", visible: :all
    assert_selector "#{discard} [data-discard-withdraws][hidden]:empty", visible: :all
    assert_selector "#{discard} form input[type=hidden][name=pending][value='']", visible: :all
    assert_selector "#{discard} [data-controller='admin--editor--publish-dialog'][data-admin--editor--publish-dialog-url-value='/cs-studio/publishing/page/#{@live.id}/changes?part=schedule'] [data-admin--editor--publish-dialog-target=discardLine]", visible: :all
  end

  test "a scheduled record's discard dialog says it goes back to what was scheduled" do
    scheduled = create_page(title: "Later", published: false)
    assert Pages::Save.call(scheduled, attributes: { published_at: 3.days.from_now }).ok?
    assert Pages::Save.call(scheduled, translations: { "en" => { title: "Typed" } }).ok?
    dialogs(scheduled)

    assert_selector "dialog#discard-changes-page-#{scheduled.id}", text: "This page goes back to what was scheduled. Blocks added since are deleted with their notes; blocks deleted since come back without theirs.", visible: :all
    assert_no_text "goes back to what is published"
  end

  test "a post's discard dialog says what a post goes back to, and with a change scheduled it says that goes too" do
    post = create_post(title: "Post")
    assert Posts::Save.call(post, translations: { "en" => { title: "Changed" } }).ok?
    publish_changes(post, at: Time.zone.local(2031, 10, 12, 9))
    dialogs(post)

    assert_selector "dialog#discard-changes-post-#{post.id}", text: "This post goes back to what is published.", visible: :all
    assert_selector "dialog#discard-changes-post-#{post.id} [data-discard-withdraws]:not([hidden])", text: "The changes scheduled for 12 Oct 2031, 09:00 are discarded as well.", visible: :all
    assert_selector "dialog#discard-changes-post-#{post.id} form input[type=hidden][name=pending][value='#{Publishing.pending(post).id}']", visible: :all
  end

  test "the cancel dialog is there only while a change is scheduled, names its time, and its form posts to cancel" do
    dialogs
    assert_no_selector "dialog[id^=cancel-scheduled-change-]", visible: :all

    publish_changes(@live, at: Time.zone.local(2031, 10, 12, 9))
    dialogs
    cancel = "dialog#cancel-scheduled-change-page-#{@live.id}"
    assert_selector "#{cancel} h2", text: "Cancel the scheduled change?", visible: :all
    assert_selector cancel, text: "The changes scheduled for 12 Oct 2031, 09:00 will not be published then. They stay in the editor as unpublished changes.", visible: :all
    assert_equal [ "Keep it scheduled", "Cancel scheduled change" ], texts("#{cancel} footer button")
    assert_selector "#{cancel} form[action='/cs-studio/publishing/page/#{@live.id}/cancel_scheduled_change'][method=post] input[type=hidden][name=pending][value='#{Publishing.pending(@live).id}']", visible: :all
    assert_selector "#{cancel} [data-controller='admin--editor--publish-dialog'] [data-admin--editor--publish-dialog-target=cancelLine]", visible: :all
  end

  test "all the forms go through the write queue's hold and replace the page" do
    publish_changes(@live, at: 2.days.from_now)
    dialogs

    assert_selector "form[data-controller='admin--saving--queue-hold'][data-action='submit->admin--saving--queue-hold#submit'][data-turbo-frame=_top]", count: 3, visible: :all
    assert_equal 3, page.all("form[method=post]", visible: :all).size
  end

  test "after a refusal it opens on load with the sentence, the choice and the typed time; junk is not echoed" do
    dialogs(error: "Pick a time in the future.", when_chosen: "at", value: "2001-01-01T09:00")
    assert_selector "#{publish_dialog}[data-admin--ui--dialog-open-on-load] [role=alert]", text: "Pick a time in the future.", visible: :all
    assert_selector "#{publish_dialog} input[type=radio][value=at][checked]", visible: :all
    assert_selector "#{publish_dialog} input[name=published_at][value='2001-01-01T09:00']", visible: :all

    dialogs(error: "Choose a date and time", when_chosen: "<b>", value: "soon<script>")
    assert_selector "#{publish_dialog} input[type=radio][value=now][checked]", visible: :all
    assert_no_selector "#{publish_dialog} input[name=published_at][value*=soon]", visible: :all

    dialogs(error: "These changes are no longer scheduled. Nothing was published.", when_chosen: "kept", value: "")
    assert_selector "#{publish_dialog} input[type=radio][value=now][checked]", visible: :all
    assert_selector "#{publish_dialog} label[hidden] input[type=radio][value=kept]:not([checked])", visible: :all
  end

  test "someone who may not publish or change the record gets no dialog" do
    dialogs(actor: users(:reader))

    assert_no_selector "dialog", visible: :all
    assert_no_selector "form", visible: :all
  end
end
