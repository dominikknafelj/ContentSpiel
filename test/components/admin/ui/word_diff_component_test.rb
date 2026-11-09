require "test_helper"

class Admin::Ui::WordDiffComponentTest < ViewComponent::TestCase
  test "deleted and inserted words carry their cue as real text, equal text is plain" do
    render_inline Admin::Ui::WordDiffComponent.new(segments: [ [ :equal, "Welcome to " ], [ :delete, "the" ], [ :insert, "our" ], [ :equal, " site" ] ])

    assert_selector "del", text: "the"
    assert_selector "del .sr-only", text: "Removed:"
    assert_selector "ins.text-ok-ink.underline", text: "our"
    assert_selector "ins .sr-only", text: "Added:"
    assert_text "Welcome to"
  end

  test "text is escaped" do
    render_inline Admin::Ui::WordDiffComponent.new(segments: [ [ :insert, "<script>x</script>" ] ])

    assert_no_selector "script"
    assert_text "<script>x</script>"
  end

  test "removed words are struck through in ink on sunken, never a danger fill, and keep their Removed cue" do
    render_inline Admin::Ui::WordDiffComponent.new(segments: [ [ :delete, "spare" ] ])

    removed = page.find("del", text: "spare")["class"].split
    %w[text-ink bg-sunken line-through decoration-meta].each { |utility| assert_includes removed, utility }
    assert_empty removed.grep(/danger/)
    assert_equal "Removed:", page.find("del > .sr-only").text.strip
  end
end
