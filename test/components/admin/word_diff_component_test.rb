require "test_helper"

class Admin::WordDiffComponentTest < ViewComponent::TestCase
  test "deleted and inserted words carry their cue as real text, equal text is plain" do
    render_inline Admin::WordDiffComponent.new(segments: [ [ :equal, "Welcome to " ], [ :delete, "the" ], [ :insert, "our" ], [ :equal, " site" ] ])

    assert_selector "del.text-danger-ink", text: "the"
    assert_selector "del .sr-only", text: "Removed:"
    assert_selector "ins.text-ok-ink.underline", text: "our"
    assert_selector "ins .sr-only", text: "Added:"
    assert_text "Welcome to"
  end

  test "text is escaped" do
    render_inline Admin::WordDiffComponent.new(segments: [ [ :insert, "<script>x</script>" ] ])

    assert_no_selector "script"
    assert_text "<script>x</script>"
  end
end
