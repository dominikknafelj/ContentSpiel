require "test_helper"

class PublishingTest < ActiveSupport::TestCase
  test "the content columns of a record or of its class" do
    page = create_page(title: "One")

    assert_equal Publishing::CONTENT.fetch("Page"), Publishing.content_columns(page)
    assert_equal Publishing::CONTENT.fetch("Post"), Publishing.content_columns(Post)
  end

  test "current, baseline, pending and copied? follow the copies of a record" do
    page = create_page(title: "One")
    first = Publishing.current(page)
    assert Publishing.copied?(page)
    assert_equal first, Publishing.baseline(page)

    later = Publishing::Version.take!(page, live_at: 2.days.from_now)

    assert_equal first, Publishing.current(page)
    assert_equal later, Publishing.pending(page)
    assert_equal later, Publishing.baseline(page)
    assert_not Publishing.copied?(create_page(title: "Draft", published: false))
  end
end
