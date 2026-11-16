require "test_helper"

# The restore dialog (the StudioHistory card, "The restore dialog"): what the
# working version becomes, the overview of what changes in it, the lines of
# what cannot come back as it was, and Restore, or Close alone when there is
# nothing to restore.
class Admin::HistoryScreen::RestoreDialogComponentTest < ViewComponent::TestCase
  include ContentHelper

  def draw(page, number)
    version = Publishing::Version.of(page.reload).find_by!(number: number)
    as(users(:one)) do
      render_inline(Admin::HistoryScreen::RestoreDialogComponent.new(record: page, version: version,
        changes: Publishing::Changes.between(page, from: :working, to: version), locale: "en"))
    end
  end

  def block(page, text = nil, **attributes)
    result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }.merge(attributes),
      translations: (text ? { "en" => { body: rich_doc(text) } } : {}))
    assert result.ok?, result.errors.to_sentence
    result.record
  end

  test "the dialog names a block that comes back without notes, an image that is gone and a schedule that stays" do
    # Version 1 is the page as created; version 2 holds its two blocks.
    page = create_page(title: "Pricing")
    gone = create_media_asset
    later = create_media_asset
    deleted = block(page, "Deleted since")
    image = block(page, block_type: "image", media_asset_id: gone.id)
    publish_changes(page)
    assert ContentBlocks::Destroy.call(deleted).ok?
    assert ContentBlocks::Save.call(image.reload, attributes: { media_asset_id: later.id }).ok?
    added = block(page, "Added since")
    assert as(users(:one)) { Notes::Start.call(added, body: "A question") }.ok?
    assert as(users(:one)) { Notes::Start.call(added, body: "Another") }.ok?
    publish_changes(page)
    gone.update_columns(trashed_at: Time.current) # version: none (a test trashes an image an older version shows)
    assert Pages::Save.call(page.reload, translations: { "en" => { title: "Pricing for teams" } }).ok?
    at = 2.days.from_now.change(hour: 9, min: 0, sec: 0)
    publish_changes(page, at: at)

    draw(page, 2)

    assert_selector "dialog[data-dialog-width=form][data-dialog-steady]"
    assert_selector "h2", text: "Restore version 2?"
    assert_text "Pricing for teams’s working version becomes version 2 as it went live on"
    assert_text "Nothing is published: the site keeps showing version 3 until you publish the changes."
    assert_selector "[data-publishing-overview] [data-change=added]", text: "Deleted since"
    assert_selector "[data-publishing-overview] [data-change=removed]", text: "Added since"
    warn = page_lines("[data-restore-warnings]")
    assert_equal [
      "1 block that comes back returns without notes: a block's notes close when it is removed.",
      "1 block that goes carries 2 notes; they close with it.",
      "1 image is no longer in the library: its block comes back empty."
    ], warn
    assert_no_selector "[data-restore-warnings][role]"
    time = I18n.l(at.in_time_zone(Current.site.effective_time_zone), format: :"admin.datetime")
    assert_selector "[data-restore-schedule]", text: "The change scheduled for #{time} stays scheduled."
    assert_selector "form[method=post][data-turbo-frame=_top][data-controller~='admin--saving--queue-hold'] input[name=number][value='2']", visible: :all
    assert_selector "input[name=shown_updated_at][value='#{page.reload.updated_at.iso8601(6)}']", visible: :all
    assert_selector "button[type=submit]", text: "Restore version 2"
    assert_selector "button", text: "Cancel"
  end

  test "a version equal to the working version offers Close alone" do
    page = create_page(title: "Pricing")

    draw(page, 1)

    assert_text "Version 1 is the same as the working version. There is nothing to restore."
    assert_no_selector "form[method=post]"
    assert_no_selector "button", text: "Restore version 1"
    assert_selector "dialog footer button", text: "Close"
    assert_no_selector "button", text: "Cancel"
    assert_no_selector "[data-restore-warnings]"
  end

  private

  def page_lines(selector) = page.find(selector).all("p").map { |line| line.text.strip }
end
