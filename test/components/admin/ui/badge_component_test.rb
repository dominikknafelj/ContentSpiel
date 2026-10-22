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
end
