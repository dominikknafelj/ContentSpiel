require "test_helper"

# "Publish now" on a scheduled record (version history spec D9): one steady
# dialog drawn with the page, whose body the server's answer fills when it
# opens; with changes saved since the schedule it asks which version goes live.
class Admin::EditorScreen::PublishNowDialogComponentTest < ViewComponent::TestCase
  include ContentHelper

  setup do
    @record = create_page(title: "Pricing", published: false)
    @at = 2.days.from_now.change(sec: 0)
    assert Pages::Save.call(@record, attributes: { published_at: @at }).ok?
  end

  def scheduled_time = I18n.l(@record.reload.published_at.in_time_zone(Current.site.effective_time_zone), format: :"admin.datetime")

  def dialog = "dialog#publish-now-page-#{@record.id}"

  def render_dialog = as(users(:one)) { render_inline Admin::EditorScreen::PublishNowDialogComponent.new(record: @record.reload, locale: "en") }

  def render_answer
    as(users(:one)) do
      render_inline Admin::EditorScreen::PublishNowDialogComponent.answer(record: @record.reload, changes: ::Publishing::State.of(@record).changes? ? ::Publishing::Changes.of(@record) : nil,
        holds: nil, locale: "en")
    end
  end

  def texts(selector) = page.all(selector, visible: :all).map { |node| node.text(:all).strip }

  test "the dialog is drawn once, steady, reading its body when it opens, with a form to the record's publish behind the queue hold" do
    render_dialog

    assert_selector "#{dialog}[data-dialog-width=form][data-dialog-steady][data-controller='admin--editor--publish-dialog']" \
      "[data-admin--editor--publish-dialog-url-value='/cs-studio/publishing/page/#{@record.id}/changes?part=publish_now']" \
      "[data-action='admin--ui--dialog:opening@window->admin--editor--publish-dialog#opening']", visible: :all
    assert_selector "#{dialog} h2", text: "Publish Pricing now?", visible: :all
    assert_selector "#{dialog} [data-admin--editor--publish-dialog-target=loading]", text: "Checking for changes saved since…", visible: :all
    assert_selector "#{dialog} [data-admin--editor--publish-dialog-target=failed][hidden][role=alert]", visible: :all
    assert_selector "#{dialog} [data-admin--editor--publish-dialog-target=overview][aria-live=polite]:empty", visible: :all
    form = "#{dialog} form#publish-now-page-#{@record.id}-form[action='/cs-studio/pages/#{@record.id}/publish'][method=post][data-turbo-frame=_top]" \
      "[data-controller='admin--saving--queue-hold'][data-action='submit->admin--saving--queue-hold#submit']"
    assert_selector form, visible: :all
    assert_selector "#{form} input[type=hidden][name=pending][value='']", visible: :all
    assert_equal [ "Cancel", "Publish now" ], texts("#{dialog} footer button")
    assert_selector "#{dialog} footer button[type=submit][form='publish-now-page-#{@record.id}-form'][data-admin--editor--publish-dialog-target=confirm]", visible: :all
    messages = JSON.parse(page.find(dialog, visible: :all)["data-messages"])
    assert_equal "Publish now", messages["components.editor_screen.publish_now_dialog.confirm"]
    assert_equal "Publish the scheduled version", messages["components.editor_screen.publish_now_dialog.choices.scheduled.title"]
    assert_equal "Publish with the later changes", messages["components.editor_screen.publish_now_dialog.choices.with_changes.title"]
  end

  test "with no changes since, the dialog says when it would have gone live and offers Publish now" do
    render_answer

    assert_selector "[data-publishing-schedule][data-pending-id='']", visible: :all
    assert_selector "[data-publishing-overview][data-publish-now=plain]", text: "It goes live now instead of at #{scheduled_time}, as scheduled."
    assert_no_selector "[role=radiogroup]"
    assert_no_selector "input[name=with_changes]", visible: :all
    assert_no_selector "details"
  end

  test "with changes since, the dialog offers the two choices, the scheduled version chosen" do
    assert Pages::Save.call(@record, translations: { "en" => { title: "Pricing, edited" } }).ok?
    render_answer

    answer = "[data-publishing-overview][data-publish-now=choice]"
    assert_selector "#{answer} p", text: "Changes were saved after it was scheduled for #{scheduled_time}."
    group = "#{answer} [role=radiogroup][aria-label='What goes live'][data-action='change->admin--editor--publish-dialog#chose']"
    form = "publish-now-page-#{@record.id}-form"
    assert_selector "#{group} label input[type=radio][name=with_changes][value='0'][form='#{form}'][checked]"
    assert_selector "#{group} label input[type=radio][name=with_changes][value='1'][form='#{form}']:not([checked])"
    assert_equal [ "Publish the scheduled version", "Publish with the later changes" ], texts("#{group} label span.font-semibold")
    assert_selector "#{group} label", text: "What was scheduled goes live now. Your later changes stay unpublished."
    assert_selector "#{group} label", text: "Everything saved so far goes live now, the later changes included."
    assert_selector "#{answer} details:not([open]) summary", text: "What changed since"
    assert_selector "#{answer} details [data-publishing-overview] [data-changed-fields]", text: "Title", visible: :all
    assert_no_text "It goes live now instead of"
  end
end
