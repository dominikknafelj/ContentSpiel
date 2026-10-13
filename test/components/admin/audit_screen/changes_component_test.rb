require "test_helper"

# The event page's field changes: word diffs per language, "Changed" for a
# body, plain old -> new otherwise, bounded, escaped, nothing secret.
class Admin::AuditScreen::ChangesComponentTest < ViewComponent::TestCase
  def render_changes(changes) = render_inline(Admin::AuditScreen::ChangesComponent.new(field_changes: changes))

  test "nothing recorded" do
    render_changes({})
    assert_text "No field changes recorded."
    render_changes(nil)
    assert_text "No field changes recorded."
  end

  test "a text change is a word diff: before strikes what left, after underlines what came in" do
    render_changes("title" => [ "Welcome to the new site", "Welcome to our new site" ])

    assert_selector "td:nth-of-type(2) del", text: "the"
    assert_selector "td:nth-of-type(2) ins", count: 0
    assert_selector "td:nth-of-type(3) ins", text: "our"
    assert_selector "td:nth-of-type(3) del", count: 0
    assert_selector "del .sr-only", text: "Removed:"
    assert_selector "ins .sr-only", text: "Added:"
    assert_text "1 FIELD"
  end

  test "an empty side reads Empty" do
    render_changes("excerpt" => [ nil, "We rebuilt everything." ], "subtitle" => [ "Old", "" ])

    assert_selector "tr", text: /excerpt\s*Empty\s*Added:\s*We rebuilt everything\./
    assert_selector "tr", text: /subtitle\s*Removed:\s*Old\s*Empty/
    assert_text "2 FIELDS"
  end

  test "grouped per language, enabled languages by their native name, others by code" do
    with_locales(%w[en de], default: "en") do
      render_changes("de title" => [ "a", "b" ], "de excerpt" => [ nil, "c" ], "en title" => [ "x", "y" ], "fr title" => [ "p", "q" ], "slug" => [ "s", "t" ])

      headings = page.all("[data-changes-group] > p").map(&:text)
      assert_equal [ "1 FIELD", "1 FIELD · ENGLISH", "2 FIELDS · DEUTSCH", "1 FIELD · FR" ], headings
    end
  end

  test "a rich-text body or digest-only change is Changed, never the digests" do
    render_changes("en body" => { "digest_before" => "aaa111", "digest_after" => "bbb222" })

    assert_selector "td[colspan='2']", text: "Changed"
    assert_no_text "aaa111"
    assert_no_text "bbb222"
  end

  # What `Audit::Snapshot` records for a `:code` field (final review I2): a
  # row of its own that says the code changed, never a digest shown as if
  # it were the code.
  test "a code field's change is Changed under the column and the field, never its digests or lengths" do
    render_changes("settings code" => { "digest_before" => "aaa111", "digest_after" => "bbb222", "length_before" => 18_000, "length_after" => 18_004 },
      "settings" => [ { "language" => "ruby" }, { "language" => "python" } ])

    assert_selector "tbody tr", count: 2
    assert_selector "tr", text: /settings code\s*Changed/
    assert_no_text "aaa111"
    assert_no_text "bbb222"
    assert_no_text "18000"
    assert_no_text "18004"
    assert_text "python"
  end

  test "other values read old -> new as text" do
    render_changes("published" => [ false, true ], "group_ids" => [ [ 1 ], [ 1, 2 ] ], "owner" => [ nil, true ])

    assert_selector "tr", text: /published\s*false\s*true/
    assert_selector "tr", text: /group_ids\s*\[1\]\s*\[1,2\]/
    assert_selector "tr", text: /owner\s*Empty\s*true/
  end

  test "text too long for a word diff says so and is cut" do
    render_changes("excerpt" => [ "alpha " * 6_000, "beta " * 6_000 ])

    assert_text "The text is too long to compare word by word."
    assert_selector "del", count: 0
    assert_operator page.text.scan("alpha").size, :<, 400
  end

  test "values are escaped text" do
    render_changes("title" => [ "<script>alert(1)</script>", "<b>bold</b>" ])

    assert_no_selector "script"
    assert_no_selector "b"
    assert_text "<b>bold</b>"
  end

  test "bookkeeping and scrubbed keys are never shown" do
    render_changes("translation_sources" => { "title" => {} }, "translation_original_changed_at" => [ nil, "x" ], "password_digest" => [ "a", "b" ],
      "ai_api_key" => [ "k1", "k2" ], "created_at" => [ "a", "b" ], "title" => [ "a", "b" ])

    assert_selector "tbody tr", count: 1
    assert_no_text "password_digest"
    assert_no_text "translation_sources"
  end
end
