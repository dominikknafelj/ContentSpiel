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

  test "with nothing chosen the summary names the versions" do
    draw(chosen_number: nil)

    assert_includes page.find("summary").text, "Versions"
  end
end
