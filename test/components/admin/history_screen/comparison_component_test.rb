require "test_helper"

# The History screen's comparison (the StudioHistory card, "The comparison"):
# the heading, the choice of the other side, the language that differs, and
# the Restore slot only where a restore is offered.
class Admin::HistoryScreen::ComparisonComponentTest < ViewComponent::TestCase
  include ContentHelper

  setup do
    @pricing = create_page(title: "Pricing")
    assert Pages::Save.call(@pricing, translations: { "de" => { title: "Preise" } }).ok?
    publish_changes(@pricing)
  end

  def draw(version: 2, with: "previous", locale: "en", restore_offered: false, &block)
    history = Publishing::History.new(@pricing.reload)
    chosen = history.find(version)
    previous = history.previous(version)
    other = with == "working" ? :working : previous
    as(users(:one)) do
      render_inline(Admin::HistoryScreen::ComparisonComponent.new(record: @pricing, version: chosen, previous: previous, with: with, numbers: history.numbers,
        changes: Publishing::Changes.between(@pricing, from: other, to: chosen), locale: locale, form_url: "/h", hidden: { version: version, page: nil },
        restore_offered: restore_offered), &block)
    end
  end

  test "the heading names the version, and the other side is the version before it, the working version or another by number" do
    draw

    assert_selector "section[aria-labelledby=history-comparison-heading] h2#history-comparison-heading", text: "Version 2"
    assert_equal [ "the version before it (1)", "the working version" ], page.all("select[name=with] option").map(&:text), "version 1 is the version before it, offered once"
    assert_selector "select[name=with] option[selected][value=previous]"
    draw(version: 1, with: "working")
    assert_equal [ "the working version", "Version 2" ], page.all("select[name=with] option").map(&:text), "the chosen version is not offered against itself"
    draw
    assert_selector "input[type=hidden][name=version][value='2']", visible: :hidden
    assert_no_selector "input[name=page]", visible: :hidden
    assert_selector "form[method=get][action='/h'][data-controller~='admin--ui--auto-submit']"
  end

  test "the language select says which languages differ, and the line under it names the others" do
    draw

    assert_equal [ "English", "Deutsch · differs", "Español" ], page.all("select[name=locale] option").map(&:text)
    assert_text "Deutsch differs; Español is the same."
    assert_text "No differences."
  end

  test "Restore stands in its slot only where it is offered" do
    draw(restore_offered: true) { |comparison| comparison.with_restore { "RESTORE" } }
    assert_selector "[data-history-restore]", text: "RESTORE"

    draw(restore_offered: false) { |comparison| comparison.with_restore { "RESTORE" } }
    assert_no_selector "[data-history-restore]"
  end
end
