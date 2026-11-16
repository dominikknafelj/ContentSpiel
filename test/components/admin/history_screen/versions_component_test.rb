require "test_helper"

# The History screen's versions: one `<details>` that is the rail where the
# list docks and a disclosure above the comparison below that, its summary
# naming the chosen version.
class Admin::HistoryScreen::VersionsComponentTest < ViewComponent::TestCase
  include ContentHelper

  setup do
    @pricing = create_page(title: "Pricing")
    assert Pages::Save.call(@pricing, translations: { "en" => { title: "Prices" } }).ok?
    publish_changes(@pricing)
  end

  def draw(chosen_number: 1)
    history = Publishing::History.new(@pricing.reload)
    as(users(:one)) do
      render_inline Admin::HistoryScreen::VersionsComponent.new(history: history, chosen: chosen_number && history.find(chosen_number),
        url: ->(number) { "/v/#{number}" }, page_url: ->(number) { "/p/#{number}" })
    end
  end

  test "the working version first, then each version newest first, the chosen one current" do
    draw

    assert_selector "details.admin-list-rail__rail[data-history-versions]:not([open])"
    assert_equal %w[working 2 1], page.all("[data-version-row]", visible: :all).map { |row| row["data-version-row"] }
    assert_selector "a[href='/v/1'][aria-current=true]", visible: :all
    assert_selector "a[href='/v/2']:not([aria-current])", visible: :all
  end

  test "the summary names the chosen version, when it went live and how many there are" do
    draw

    summary = page.find("summary")
    assert_includes summary.text, "Version 1"
    assert_includes summary.text, "Went live"
    assert_includes summary.text, "· 2 versions"
  end

  test "a scheduled record's summary names the record's time" do
    later = create_page(title: "Later")
    at = 3.days.from_now.change(hour: 9, min: 0)
    later.update_columns(published_at: at) # version: none (a test schedules a page) # changes: none (a test schedules a page)
    history = Publishing::History.new(later.reload)
    as(users(:one)) do
      render_inline Admin::HistoryScreen::VersionsComponent.new(history: history, chosen: history.find(1), url: ->(number) { "/v/#{number}" }, page_url: ->(number) { "/p/#{number}" })
    end

    date = I18n.l(at.in_time_zone(Current.site.effective_time_zone).to_date, format: :"admin.short_with_year")
    assert_includes page.find("summary").text, "Goes live #{date}"
  end

  test "with nothing chosen the summary names the versions" do
    draw(chosen_number: nil)

    assert_includes page.find("summary").text, "Versions"
  end
end
