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

  # A new column on one of the three tables must be decided: in the copy, left
  # on the rows with a reason, or never stored. Not "forgotten", not twice.
  { "Page" => Page, "Post" => Post, "ContentBlock" => ContentBlock }.each do |name, model|
    test "every column of #{model.table_name} is in exactly one of the copy, the rows and never stored" do
      lists = { "CONTENT" => Publishing::CONTENT.fetch(name), "ROWS" => Publishing::ROWS.fetch(name).keys,
                "NEVER_STORED" => Publishing::NEVER_STORED.fetch(name).keys }
      placed = lists.values.flatten

      assert_empty model.column_names - placed, "#{model.table_name} has columns in none of Publishing::CONTENT, ROWS and NEVER_STORED: decide where each goes"
      assert_empty placed - model.column_names, "Publishing names columns #{model.table_name} does not have"
      assert_equal placed.uniq.sort, placed.sort, "a column of #{model.table_name} is in two lists: #{placed.tally.select { |_, n| n > 1 }.keys}"
      assert Publishing::ROWS.fetch(name).values.all?(&:present?), "every column left on the rows needs its reason"
    end
  end
end
