require "test_helper"

# Contrast and buttons spec (D1, Ruling 13): a badge says something and
# cannot be pressed, so it has a sunken fill and no outline; only a button has one.
class Admin::Ui::BadgeComponentTest < ViewComponent::TestCase
  test "a badge is a sunken mono label with no border, and passes its own attributes through" do
    render_inline Admin::Ui::BadgeComponent.new(label: "Default", data: { default_tag: true })
    classes = page.find("span[data-default-tag]", text: "Default")["class"].split

    assert_includes classes, "bg-sunken"
    assert_includes classes, "text-meta"
    assert_includes classes, "text-label"
    assert_empty classes.grep(/\Aborder/)
  end

  test "the warn tone is the warn tint with the warn ink" do
    render_inline Admin::Ui::BadgeComponent.new(label: "NO ALT", tone: :warn)
    assert_selector "span.bg-warn-tint.text-warn-ink", text: "NO ALT"
  end

  test "an unknown tone is a programming error" do
    assert_raises(ArgumentError) { Admin::Ui::BadgeComponent.new(label: "x", tone: :loud) }
  end

  test "a mark stands before the label, hidden from a screen reader" do
    render_inline(Admin::Ui::BadgeComponent.new(label: "Blog post", data: { scope_chip: true })) do |badge|
      badge.with_mark { '<span class="dot"></span>'.html_safe }
    end

    badge = page.find("span[data-scope-chip]")
    assert_equal "Blog post", badge.text.squish
    mark = badge.find(:xpath, "./*[1]", visible: :all)
    assert_equal "true", mark["aria-hidden"]
    assert_equal Admin::Ui::BadgeComponent::MARK_CLASS, mark[:class]
    assert mark.has_css?("span.dot", visible: :all), "the caller's mark is inside the hidden part"
    assert badge.native.inner_html.index("dot") < badge.native.inner_html.index("Blog post"), "the mark comes before the label"
  end
end
