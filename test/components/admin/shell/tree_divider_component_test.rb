require "test_helper"

# The page tree's divider as the server draws it (Claude Design, 2026-10-13,
# T1): a focusable separator that says its width, with the shared tooltip and
# the numbers its script works with. What it does is a browser's to show
# (`test/system/admin/tree_column_test.rb`).
class Admin::Shell::TreeDividerComponentTest < ViewComponent::TestCase
  Divider = Admin::Shell::TreeDividerComponent

  test "a vertical separator in the Tab order that says the default width between the minimum and the maximum, by name" do
    render_inline(Divider.new)

    assert_selector "div.admin-tree-divider[role=separator][aria-orientation=vertical][tabindex='0'][aria-controls=tree-column]", count: 1
    assert_selector "[role=separator][aria-valuenow='272'][aria-valuemin='220'][aria-valuemax='480']"
    assert_selector "[role=separator][aria-label='#{I18n.t("admin.components.shell.tree_divider.label")}']"
    assert_equal "Page tree width", I18n.t("admin.components.shell.tree_divider.label")
  end

  test "the numbers are the design's, and the default is the 17rem the column always was" do
    assert_equal [ 220, 272, 480, 640, 240, 400 ], [ Divider::MIN, Divider::DEFAULT, Divider::MAX, Divider::EDITOR, Divider::SIDEBAR, Divider::NOTES ]
    assert_equal 17 * Divider::BASE, Divider::DEFAULT
    # The design's own sum: at the default the tree stays beside the notes from a 1552px window.
    assert_equal 1552, Divider::SIDEBAR + Divider::DEFAULT + Divider::NOTES + Divider::EDITOR
  end

  # The figures are pixels at a 16px root font, and the stylesheet lays them
  # out in rem: each of them as a rem literal is in the shell's rules, and none
  # is left there as pixels (the notes column's 400px is the one that is).
  test "the stylesheet holds every figure in rem, as the constants over the base: none as pixels" do
    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read
    rules = css[/^:root \{\n  --admin-tree-room:.*?^\.admin-shell--tree \{[^\n]*\n/m]
    assert rules, "the tree column's rules moved"
    rem = ->(pixels) { format("%g", pixels.fdiv(Divider::BASE)) + "rem" }

    assert_equal %w[13.75rem 17rem 30rem 40rem 15rem], [ Divider::MIN, Divider::DEFAULT, Divider::MAX, Divider::EDITOR, Divider::SIDEBAR ].map(&rem)
    assert_includes rules, "--admin-tree-room: calc(100vw - #{rem.(Divider::SIDEBAR)} - #{rem.(Divider::EDITOR)});"
    assert_includes rules, "--admin-tree-column: clamp(#{rem.(Divider::MIN)}, var(--admin-tree-width, #{rem.(Divider::DEFAULT)}), max(#{rem.(Divider::MIN)}, min(#{rem.(Divider::MAX)}, var(--admin-tree-room))));"
    assert_includes rules, "@media (max-width: 1279px) { :root { --admin-tree-room: calc(100vw - #{rem.(Divider::EDITOR)}); } }"
    assert_no_match(/\d+px(?! \{)/, rules.gsub("1279px", ""), "a pixel length among the tree column's rules")
    assert_match(/^:root \{ --admin-notes-width: #{Divider::NOTES}px; \}/, css)
  end

  test "the script is handed every number and the storage key as values, and the tooltip's sentence as a message" do
    render_inline(Divider.new)
    divider = page.find("[role=separator]")

    assert_equal %w[admin--ui--tooltip admin--shell--tree-width], divider["data-controller"].split
    { min: 220, default: 272, max: 480, editor: 640, sidebar: 240, notes: 400, key: "cs-tree-width" }.each do |name, value|
      assert_equal value.to_s, divider["data-admin--shell--tree-width-#{name}-value"], name.to_s
    end
    messages = JSON.parse(divider["data-messages"])
    assert_equal "Tree width %{width}px. Arrow keys to resize.", messages.fetch("components.shell.tree_divider.tooltip")
  end

  test "every gesture has its action: the press that begins a drag, a double click, the keys, and what keeps the values current" do
    render_inline(Divider.new)
    actions = page.find("[role=separator]")["data-action"].split

    %w[pointerdown->admin--shell--tree-width#press lostpointercapture->admin--shell--tree-width#release blur@window->admin--shell--tree-width#release
       pointerenter->admin--shell--tree-width#enter pointerleave->admin--shell--tree-width#leave
       dblclick->admin--shell--tree-width#reset keydown->admin--shell--tree-width#key
       resize@window->admin--shell--tree-width#sync turbo:before-cache@document->admin--shell--tree-width#rest].each do |action|
      assert_includes actions, action
    end
    # The shared tooltip's own, unchanged: the divider is its host.
    Admin::Ui::TooltipComponent::ACTIONS.split.each { |action| assert_includes actions, action }
  end

  test "the shared tooltip is inside, hidden until asked for, and names the default width" do
    render_inline(Divider.new)

    assert_selector "[role=separator] .admin-tree-divider__tip [data-tooltip][data-admin--ui--tooltip-target=bubble]", visible: :all, count: 1,
      text: "Tree width 272px. Arrow keys to resize."
    assert page.find("[data-tooltip]", visible: :all)["hidden"]
  end
end
