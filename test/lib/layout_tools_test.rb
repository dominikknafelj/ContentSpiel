require "test_helper"
require Rails.root.join("script/layout/identifiers.rb").to_s

# The matching of script/layout/identifiers.rb, the tool of the source layout cleanup.
# Deleted with the tools in the plan's last task (Task 9).
class LayoutToolsTest < ActiveSupport::TestCase
  def rewrite(text, pairs)
    LayoutIdentifiers.rewrite(text, pairs, "f.erb")
  end

  NOTES_LIVE = { "admin--notes-live" => "admin--notes--live" }.freeze

  test "data attributes of every kind follow their controller" do
    [ "data-admin--notes-live-unread-url-value", "data-admin--notes-live-id-param", 'data-admin--notes-live-target="button"', "data-admin--notes-live-open-class" ].each do |text|
      assert_equal text.sub("admin--notes-live", "admin--notes--live"), rewrite(text, NOTES_LIVE).first
    end
  end

  test "the underscore spelling of a Ruby hash key follows its controller, and a second run changes nothing" do
    text = "data: { admin__notes_live_unread_url_value: 1, admin__notes_live: 2 }"
    once = rewrite(text, NOTES_LIVE).first
    assert_equal "data: { admin__notes__live_unread_url_value: 1, admin__notes__live: 2 }", once
    assert_equal once, rewrite(once, NOTES_LIVE).first
  end

  test "an underscore key preceded by a word character is not an identifier" do
    text = "xadmin__notes_live_foo my_admin__notes_live"
    assert_equal text, rewrite(text, NOTES_LIVE).first
  end

  test "a leftover of an earlier move is not taken for its shorter sibling" do
    text = "admin--notes-live-target"
    out, review = rewrite(text, { "admin--notes" => "admin--notes--x" })
    assert_equal text, out
    assert_match(/leftover of an earlier move/, review.join)
  end

  test "a mixed spelling is reported and left alone" do
    out, review = rewrite("admin--notes_live", { "admin--notes" => "admin--notes--x" })
    assert_equal "admin--notes_live", out
    assert_match(/mixed spelling/, review.join)
  end

  test "review lines carry a line number" do
    _, review = rewrite("a\nb\nadmin--notes_live", { "admin--notes" => "admin--notes--x" })
    assert_match(/\Af\.erb:3: /, review.first)
  end

  test "an already rewritten token is left alone" do
    text = "admin--notes--live-target data-admin--notes--live-id-param"
    assert_equal text, rewrite(text, NOTES_LIVE).first
  end
end
