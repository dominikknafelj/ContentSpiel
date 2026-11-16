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

  test "tiles drawn together are one native group: one name, one checked, no tabindex" do
    html = [ tile(checked: true), Admin::Ui::ChoiceTileComponent.new(name: "publish[choice]", value: "later", title: "Later", line: "x") ]
      .map { |component| render_inline(component).to_html }.join
    fragment = Capybara.string(html)
    assert_equal 2, fragment.all("input[type=radio][name='publish[choice]']").size
    assert_equal 1, fragment.all("input[checked]").size
    assert_equal 0, fragment.all("input[tabindex]").size
  end
end
