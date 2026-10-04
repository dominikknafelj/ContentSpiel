require "test_helper"

class Public::PreviewBarComponentTest < ActiveSupport::TestCase
  include ComponentTestHelper

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @root = Page.create!(title: "Home", slug: "", published_at: 1.day.ago)
  end

  test "a labelled region: the label, the title, the status in words and the language's own name" do
    page = Page.create!(parent: @root, title: "About", published_at: nil)

    render_inline(Public::PreviewBarComponent.new(record: page, locale: "en"))

    assert_selector "[role=region][aria-label=Preview]", text: "Preview"
    assert_selector "span.truncate", text: "About"
    assert_text "Draft"
    assert_text "English"
  end

  test "the bar is fixed, 36px high and carries only theme tokens" do
    render_inline(Public::PreviewBarComponent.new(record: Page.create!(parent: @root, title: "About"), locale: "en"))

    assert_selector "[role=region].fixed.top-0.h-9.bg-preview-bg.text-preview-ink"
    assert_no_selector "[class*='dark:']"
    assert_no_match(/#\h{3,8}\b|rgba?\(|hsla?\(/, rendered_content)
  end

  test "a title with markup is escaped" do
    page = Page.create!(parent: @root, title: "<script>x</script>")

    render_inline(Public::PreviewBarComponent.new(record: page, locale: "en"))

    assert_no_selector "script"
    assert_selector "span.truncate", text: "<script>x</script>"
  end

  test "Scheduled and Live read as words" do
    scheduled = Page.create!(parent: @root, title: "Soon", published_at: 2.days.from_now)
    live = Page.create!(parent: @root, title: "Now", published_at: 1.day.ago)

    render_inline(Public::PreviewBarComponent.new(record: scheduled, locale: "en"))
    assert_text "Scheduled"
    render_inline(Public::PreviewBarComponent.new(record: live, locale: "en"))
    assert_text "Live"
  end

  test "both links are in the bar, Edit first, so they are the first tab stops" do
    page = Page.create!(parent: @root, title: "About")

    render_inline(Public::PreviewBarComponent.new(record: page, locale: "en"))

    assert_equal [ "Edit", "Exit preview" ], page_links
  end

  private
    def page_links = page.all("a").map(&:text)
end
