require "test_helper"

# The tree column's divider as the server draws it: a focusable separator
# that says its width, in the words of what the column holds, with the shared
# tooltip and the numbers its script works with. What it does is a browser's
# to show (`test/system/admin/tree_column_test.rb`).
class Admin::Shell::TreeDividerComponentTest < ViewComponent::TestCase
  Divider = Admin::Shell::TreeDividerComponent

  test "a vertical separator in the Tab order that says the default width between the minimum and the maximum, by name" do
    render_inline(Divider.new(subject: "pages"))

    assert_selector "div.admin-tree-divider[role=separator][aria-orientation=vertical][tabindex='0'][aria-controls=tree-column]", count: 1
    assert_selector "[role=separator][aria-valuenow='272'][aria-valuemin='220'][aria-valuemax='480']"
    assert_selector "[role=separator][aria-label='#{I18n.t("admin.components.shell.tree_subject.pages.divider")}']"
    assert_equal "Page tree width", I18n.t("admin.components.shell.tree_subject.pages.divider")
  end

  test "the fold buttons, the divider and the top bar's tree button say what the column holds" do
    render_inline(Divider.new(subject: "mind_graph"))
    divider = page.find("[role=separator]")

    assert_equal "List width", divider["aria-label"]
    assert_selector "[role=separator] [data-tooltip]", visible: :all, text: "List width 272px. Arrow keys to resize."
    key = "components.shell.tree_subject.mind_graph.divider_tooltip"
    assert_equal({ "@locale" => "en", key => "List width %{width}px. Arrow keys to resize." }, JSON.parse(divider["data-messages"]))
    assert_equal key, Divider.column_data(subject: "mind_graph")[:"admin--shell--tree-width-tooltip-key-value"]
    assert_raises(KeyError) { Divider.new(subject: "posts") }
    assert_raises(KeyError) { Divider.column_data(subject: "posts") }
  end

  test "the numbers are the design's, and the default is the 17rem the column always was" do
    assert_equal [ 220, 272, 480, 640, 240, 44 ], [ Divider::MIN, Divider::DEFAULT, Divider::MAX, Divider::EDITOR, Divider::SIDEBAR, Divider::STRIP ]
    assert_equal 17 * Divider::BASE, Divider::DEFAULT
    assert_not Divider.const_defined?(:NOTES, false), "the tree never folds for the notes: nothing counts them beside it"
  end

  # The figures are pixels at a 16px root font, and the stylesheet lays them
  # out in rem: each of them as a rem literal is in the shell's rules, and none
  # is left there as pixels.
  test "the stylesheet holds every figure in rem, as the constants over the base: none as pixels" do
    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read
    rules = css[/^:root \{\n  --admin-tree-room:.*?^\.admin-shell--tree \{[^\n]*\n/m]
    assert rules, "the tree column's rules moved"
    rem = ->(pixels) { format("%g", pixels.fdiv(Divider::BASE)) + "rem" }

    assert_equal %w[13.75rem 17rem 30rem 40rem 15rem], [ Divider::MIN, Divider::DEFAULT, Divider::MAX, Divider::EDITOR, Divider::SIDEBAR ].map(&rem)
    assert_includes rules, "--admin-tree-room: calc(100% - #{rem.(Divider::SIDEBAR)} - #{rem.(Divider::EDITOR)});"
    assert_includes rules, "--admin-tree-column: clamp(#{rem.(Divider::MIN)}, var(--admin-tree-width, #{rem.(Divider::DEFAULT)}), max(#{rem.(Divider::MIN)}, min(#{rem.(Divider::MAX)}, var(--admin-tree-room))));"
    assert_includes rules, "@media (max-width: 1279px) { :root { --admin-tree-room: calc(100% - #{rem.(Divider::EDITOR)}); } }"
    assert_no_match(/\d+px(?! \{)/, rules.gsub("1279px", ""), "a pixel length among the tree column's rules")
    assert_no_match(/--admin-notes-width/, css)
    assert_match(/^:root \{ --admin-tree-strip: #{rem.(Divider::STRIP)}; \}/, css)
  end

  test "the column carries the controller, every number and both storage keys as its values, and the actions that keep it current" do
    data = Divider.column_data(subject: "pages")

    assert_equal "admin--shell--tree-width", data[:controller]
    { min: 220, default: 272, max: 480, editor: 640, sidebar: 240, key: "cs-tree-width", "fold-key": "cs-tree-folded",
      "tooltip-key": "components.shell.tree_subject.pages.divider_tooltip" }.each do |name, value|
      assert_equal value, data[:"admin--shell--tree-width-#{name}-value"], name.to_s
    end
    assert_empty data.keys.grep(/notes|strip/), "the script counts neither the notes nor the strip"
    assert_equal %w[resize@window->admin--shell--tree-width#sync turbo:frame-load@document->admin--shell--tree-width#sync
                    turbo:before-cache@document->admin--shell--tree-width#rest], data[:action].split
  end

  test "the divider is the controller's divider target, the tooltip's host, and hands over the tooltip's sentence as a message" do
    render_inline(Divider.new(subject: "pages"))
    divider = page.find("[role=separator]")

    assert_equal %w[admin--ui--tooltip], divider["data-controller"].split
    assert_equal "divider", divider["data-admin--shell--tree-width-target"]
    assert_empty divider.native.attributes.keys.grep(/-value\z/), "the values are the column's"
    messages = JSON.parse(divider["data-messages"])
    assert_equal "Tree width %{width}px. Arrow keys to resize.", messages.fetch("components.shell.tree_subject.pages.divider_tooltip")
  end

  test "every gesture has its action on the divider: the press that begins a drag, a double click, the keys and the focus" do
    render_inline(Divider.new(subject: "pages"))
    actions = page.find("[role=separator]")["data-action"].split

    %w[pointerdown->admin--shell--tree-width#press lostpointercapture->admin--shell--tree-width#release blur@window->admin--shell--tree-width#release
       pointerenter->admin--shell--tree-width#enter pointerleave->admin--shell--tree-width#leave
       dblclick->admin--shell--tree-width#reset keydown->admin--shell--tree-width#key focus->admin--shell--tree-width#sync].each do |action|
      assert_includes actions, action
    end
    # The shared tooltip's own, unchanged: the divider is its host.
    Admin::Ui::TooltipComponent::ACTIONS.split.each { |action| assert_includes actions, action }
  end

  test "the shared tooltip is inside, hidden until asked for, and names the default width" do
    render_inline(Divider.new(subject: "pages"))

    assert_selector "[role=separator] .admin-tree-divider__tip [data-tooltip][data-admin--ui--tooltip-target=bubble]", visible: :all, count: 1,
      text: "Tree width 272px. Arrow keys to resize."
    assert page.find("[data-tooltip]", visible: :all)["hidden"]
  end
end
