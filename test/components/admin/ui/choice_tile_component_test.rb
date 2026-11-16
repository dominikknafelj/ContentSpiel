require "test_helper"

class Admin::Ui::ChoiceTileComponentTest < ViewComponent::TestCase
  def tile(**options)
    Admin::Ui::ChoiceTileComponent.new(name: "publish[choice]", value: "scheduled", title: "Publish the scheduled version", line: "What was scheduled goes live now.", **options)
  end

  test "a tile is a labelled radio with its title and line" do
    render_inline(tile(id: "choice-scheduled"))
    assert_selector "label.rounded-tile.border-line-strong.p-3 input#choice-scheduled[type=radio][name='publish[choice]'][value=scheduled]"
    assert_selector "label span.font-semibold", text: "Publish the scheduled version"
    assert_selector "label span.text-small.text-dim", text: "What was scheduled goes live now."
    assert_no_selector "input[checked]"
  end

  test "a checked tile is checked, and its edge and tint follow the radio" do
    render_inline(tile(checked: true))
    assert_selector "input[type=radio][checked]"
    assert_selector "label.has-\\[\\:checked\\]\\:border-accent.has-\\[\\:checked\\]\\:bg-accent-tint"
  end

  test "form and html pass through" do
    render_inline(tile(form: "publish-form", html: { data: { role: "tile" } }))
    assert_selector "label[data-role=tile] input[form=publish-form]"
  end

  test "tiles of one name are native radios of one group, so the arrow keys move the choice" do
    render_inline(tile(checked: true))
    first = page.find("input")
    render_inline(Admin::Ui::ChoiceTileComponent.new(name: "publish[choice]", value: "later", title: "Later", line: "x"))
    assert_equal "publish[choice]", first[:name]
    assert_selector "input[type=radio][name='publish[choice]'][value=later]"
    assert_no_selector "input[tabindex]"
  end
end
