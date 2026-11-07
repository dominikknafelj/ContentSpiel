require "test_helper"

class Admin::Ui::ButtonComponentTest < ViewComponent::TestCase
  test "renders a button with the given label and defaults to type button, variant primary" do
    render_inline Admin::Ui::ButtonComponent.new(label: "Save")

    assert_selector "button[type='button']", text: "Save"
  end

  test "secondary and danger variants render distinct classes" do
    render_inline Admin::Ui::ButtonComponent.new(label: "Cancel", variant: :secondary)
    secondary_class = page.find("button")["class"]

    render_inline Admin::Ui::ButtonComponent.new(label: "Delete", variant: :danger)
    danger_class = page.find("button")["class"]

    refute_equal secondary_class, danger_class
  end

  test "passes through arbitrary html attributes, e.g. type submit and data attributes" do
    render_inline Admin::Ui::ButtonComponent.new(label: "Add row", type: "submit", data: { action: "click->admin--editor--groups#add" })

    assert_selector "button[type='submit'][data-action='click->admin--editor--groups#add']", text: "Add row"
  end

  test "every variant drops its transition and the press's movement under reduced motion" do
    Admin::Ui::ButtonComponent::VARIANT_CLASSES.each_key do |variant|
      %i[regular small].each do |size|
        classes = Admin::Ui::ButtonComponent.classes(variant, size: size).split
        assert_includes classes, "motion-reduce:transition-none", "#{variant} (#{size}) keeps its transition under reduced motion"
        classes.grep(/active:translate-/).reject { |name| name.start_with?("motion-reduce:") }.each do |press|
          assert_includes classes, "motion-reduce:#{press.sub(/translate-y-\w+\z/, 'translate-y-0')}", "#{variant}'s press #{press} moves under reduced motion"
        end
      end
    end
    assert_includes Admin::Ui::ButtonComponent.classes(:primary).split, "motion-reduce:not-disabled:active:translate-y-0"
  end

  test "rejects an unknown variant" do
    assert_raises(ArgumentError) { Admin::Ui::ButtonComponent.new(label: "Save", variant: :nope) }
  end

  test "the primary is a solid accent fill raised to shadow 2, and hovered it darkens and rises to shadow 3" do
    render_inline Admin::Ui::ButtonComponent.new(label: "Save")
    classes = page.find("button")["class"].split

    %w[bg-accent text-on-accent shadow-2 not-disabled:hover:bg-accent-hover not-disabled:hover:shadow-3
       not-disabled:active:translate-y-px not-disabled:active:shadow-none].each { |name| assert_includes classes, name }
  end

  # The owner's decision of 2026-11-07: a tinted fill alone is no shape on
  # a rail, so the secondary carries an edge at rest, and its hover is a
  # stronger fill with the neutral lift.
  test "the secondary is a tinted fill with accent words inside a field-line edge, hovered to the press fill and shadow 2" do
    render_inline Admin::Ui::ButtonComponent.new(label: "Preview", variant: :secondary)
    classes = page.find("button")["class"].split

    %w[bg-accent-tint text-accent border-field-line not-disabled:hover:bg-accent-press not-disabled:hover:shadow-2].each { |name| assert_includes classes, name }
    assert_not_includes classes, "border-transparent"
  end

  test "the tertiary is accent words with no fill, hovered to the press fill and an underline, and ghost is no variant" do
    render_inline Admin::Ui::ButtonComponent.new(label: "Cancel", variant: :tertiary)
    classes = page.find("button")["class"].split

    %w[text-accent bg-transparent border-transparent not-disabled:hover:underline not-disabled:hover:bg-accent-press].each { |name| assert_includes classes, name }
    assert_empty classes.grep(/hover:shadow/), "a text button does not rise"
    assert_raises(ArgumentError) { Admin::Ui::ButtonComponent.new(label: "x", variant: :ghost) }
  end

  test "secondary and danger_text draw their edge, small ones in the variant's ink" do
    edge = ->(variant, size) { Admin::Ui::ButtonComponent.classes(variant, size: size).split.grep(/\Aborder-/) }
    assert_equal %w[border-field-line], edge.(:secondary, :regular)
    assert_equal %w[border-field-line], edge.(:danger_text, :regular)
    assert_equal %w[border-accent], edge.(:secondary, :small)
    assert_equal %w[border-danger], edge.(:danger_text, :small)
    %i[primary tertiary danger].each do |variant|
      %i[regular small].each { |size| assert_equal %w[border-transparent], edge.(variant, size), "#{variant} #{size}" }
    end
  end

  test "a small tertiary is underlined at rest, 3px under its words, and its hover thickens the line to 2px" do
    small = Admin::Ui::ButtonComponent.classes(:tertiary, size: :small).split
    %w[underline underline-offset-3 not-disabled:hover:decoration-2 not-disabled:hover:bg-accent-press].each { |name| assert_includes small, name }
    regular = Admin::Ui::ButtonComponent.classes(:tertiary).split
    assert_not_includes regular, "underline", "a regular tertiary is underlined only under the pointer"
  end

  # Accent is for the focus ring and for a selection: a hover that drew an
  # accent outline, ring or shadow would read as a second focused button.
  # The edge belongs to the rest, so no hover changes it either.
  test "no hover draws the accent outline or an accent shadow, and no hover changes the edge" do
    Admin::Ui::ButtonComponent::VARIANT_CLASSES.each_key do |variant|
      %i[regular small].each do |size|
        hovers = Admin::Ui::ButtonComponent.classes(variant, size: size).split.grep(/hover:/)
        assert_empty hovers.grep(/hover:(?:outline|ring|border|shadow-accent|drop-shadow|inset-shadow)/), "#{variant} #{size}: #{hovers.inspect}"
        shadows = hovers.grep(/hover:shadow/)
        assert_empty shadows - %w[not-disabled:hover:shadow-2 not-disabled:hover:shadow-3], "#{variant} #{size}: a hover lift is a neutral elevation"
      end
    end
    assert_equal %w[not-disabled:hover:shadow-3], Admin::Ui::ButtonComponent.classes(:primary).split.grep(/hover:shadow/), "the primary rises to shadow 3"
  end

  test "a hover fades its fill and its lift over 120ms on --cs-ease" do
    %w[transition-[background-color,box-shadow] duration-120 ease-(--cs-ease)].each { |name| assert_includes Admin::Ui::ButtonComponent::COMMON_CLASS.split, name }
    assert_not_includes Admin::Ui::ButtonComponent::COMMON_CLASS.split, "transition-colors"
  end

  test "every variant drops its transition and the press's movement under reduced motion" do
    Admin::Ui::ButtonComponent::VARIANT_CLASSES.each_key do |variant|
      %i[regular small].each do |size|
        classes = Admin::Ui::ButtonComponent.classes(variant, size: size).split
        assert_includes classes, "motion-reduce:transition-none", "#{variant} #{size}"
        moves = classes.grep(/active:translate/)
        assert_includes classes, "motion-reduce:not-disabled:active:translate-y-0", "#{variant} #{size}" if moves.any?
      end
    end
    assert_includes Admin::Ui::ButtonComponent.classes(:primary).split, "not-disabled:active:translate-y-px", "the press moves where motion is allowed"
    assert_includes Admin::Ui::ButtonComponent.classes(:primary).split, "not-disabled:active:shadow-none", "and under reduced motion it is told by the shadow alone"
  end

  test "the danger confirm's words are the on-danger token, never a white literal" do
    render_inline Admin::Ui::ButtonComponent.new(label: "Delete", variant: :danger)
    classes = page.find("button")["class"].split

    assert_includes classes, "bg-danger"
    assert_includes classes, "text-on-danger"
    assert_not_includes classes, "text-white"
  end

  test "danger_text is red words on the sunken fill inside a field-line edge, hovered to the danger press fill; danger_outline is gone" do
    render_inline(Admin::Ui::ButtonComponent.new(label: "Move to trash", variant: :danger_text))
    assert_selector "button.bg-sunken.text-danger-ink.border-field-line", text: "Move to trash"
    assert_selector "button[class~='not-disabled:hover:bg-danger-press'][class~='not-disabled:hover:shadow-2']"
    assert_no_selector "button.bg-accent-tint"
    assert_raises(ArgumentError) { Admin::Ui::ButtonComponent.new(label: "x", variant: :danger_outline) }
  end

  test "every variant has the accent focus ring 2px out and the button radius" do
    Admin::Ui::ButtonComponent::VARIANT_CLASSES.each_key do |variant|
      classes = Admin::Ui::ButtonComponent.classes(variant).split
      %w[focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent rounded-button font-semibold].each { |name| assert_includes classes, name, variant }
      small = Admin::Ui::ButtonComponent.classes(variant, size: :small).split
      assert_includes small, "rounded-button-sm", variant
      assert_not_includes small, "rounded-button", variant
    end
  end

  test "classes(variant) is what the component draws, so the wizard's buttons are the same" do
    Admin::Ui::ButtonComponent::VARIANT_CLASSES.each_key do |variant|
      render_inline Admin::Ui::ButtonComponent.new(label: "x", variant: variant)
      assert_equal Admin::Ui::ButtonComponent.classes(variant), page.find("button")["class"], variant
    end
    assert_raises(ArgumentError) { Admin::Ui::ButtonComponent.classes(:ghost) }

    helper = Object.new.extend(SetupHelper)
    assert_equal Admin::Ui::ButtonComponent.classes(:primary), helper.setup_primary_button_class
    assert_equal Admin::Ui::ButtonComponent.classes(:secondary), helper.setup_secondary_link_class
    assert_equal Admin::Ui::ButtonComponent.classes(:tertiary), helper.setup_tertiary_link_class
    assert_includes helper.setup_primary_button_class.split, "inline-flex"
  end

  test "no variant answers the pointer while disabled: every hover is not-disabled:hover:" do
    Admin::Ui::ButtonComponent::VARIANT_CLASSES.each do |variant, classes|
      assert_empty classes.split.grep(/\Ahover:/), variant
    end
  end

  # Contrast and buttons spec (D1, Ruling 11): one disabled look for every
  # variant, sunken with meta words and a hairline, no accent and no opacity;
  # a busy button (`aria-busy`) keeps its variant's look.
  test "every variant is drawn disabled the same way, and a busy one is not" do
    Admin::Ui::ButtonComponent::VARIANT_CLASSES.each_key do |variant|
      render_inline Admin::Ui::ButtonComponent.new(label: "Save", variant: variant, disabled: true)
      classes = page.find("button[disabled]")["class"].split

      %w[disabled:not-aria-busy:bg-sunken disabled:not-aria-busy:text-meta disabled:not-aria-busy:shadow-none aria-busy:cursor-progress].each do |name|
        assert_includes classes, name, variant
      end
      assert_empty classes.grep(/opacity-50|border-line/), variant
    end
  end

  # A disabled button must not change size: the save bar's Save is toggled by
  # script, so every variant has its 1px border at rest and the disabled look
  # only recolours it.
  test "every variant has a 1px border at rest, transparent or its edge, so no state changes a size, and disabled draws no hairline" do
    Admin::Ui::ButtonComponent::VARIANT_CLASSES.each_key do |variant|
      %i[regular small].each do |size|
        classes = Admin::Ui::ButtonComponent.classes(variant, size: size).split
        assert_includes classes, "border", "#{variant} #{size}"
        assert_equal 1, classes.grep(/\Aborder-(?:transparent|field-line|accent|danger)\z/).size, "#{variant} #{size}: one edge colour"
        assert_includes classes, "disabled:not-aria-busy:border-transparent", "#{variant} #{size}: the disabled look has no edge"
      end
    end
  end

  test "solid danger stays the dialog confirm, hovered to the darker danger fill and shadow 2" do
    render_inline Admin::Ui::ButtonComponent.new(label: "Delete", variant: :danger)
    assert_selector "button.bg-danger", text: "Delete"
    classes = page.find("button")["class"].split
    %w[not-disabled:hover:bg-danger-hover not-disabled:hover:shadow-2].each { |name| assert_includes classes, name }
    assert_empty classes.grep(/opacity/), "the hover is a fill, never a fade"
  end

  test "small swaps the padding for a compact one and keeps the variant" do
    render_inline Admin::Ui::ButtonComponent.new(label: "Use", size: :small)
    assert_selector "button.bg-accent.px-2.py-0\\.5.text-sm", text: "Use"
    assert_no_selector "button.px-4"
    assert_raises(ArgumentError) { Admin::Ui::ButtonComponent.new(label: "x", size: :huge) }
  end

  # An icon button shows only its icon: the label is its name and the shared
  # tooltip's text, and the tooltip's controller and actions come before the
  # caller's own, which are kept.
  test "an icon button draws the icon, names itself with the label and hosts the shared tooltip, keeping the caller's data" do
    render_inline Admin::Ui::ButtonComponent.new(label: "Hide page tree", variant: :tertiary, size: :small, icon: :panel_left_close,
      aria: { controls: "tree-column" }, data: { action: "admin--shell--tree-width#fold", "admin--shell--tree-width-target": "fold" })
    button = page.find("button")

    assert_equal "Hide page tree", button["aria-label"]
    assert_equal "tree-column", button["aria-controls"]
    assert_equal "fold", button["data-admin--shell--tree-width-target"]
    assert_equal "admin--ui--tooltip", button["data-controller"]
    assert_equal Admin::Ui::TooltipComponent::ACTIONS.split + %w[admin--shell--tree-width#fold], button["data-action"].split
    assert_includes button["class"].split, Admin::Ui::TooltipComponent::HOST
    assert_selector "button > svg[aria-hidden=true]", count: 1
    assert_selector "button [data-tooltip][hidden]", visible: :all, text: "Hide page tree"
    assert_equal %w[svg span], button.native.children.reject { |node| node.text? && node.text.strip.empty? }.map(&:name), "an icon button shows no words beside its icon and the hidden tooltip"
  end

  test "an icon button refuses a blank label: it would have no name" do
    [ nil, "", "  " ].each do |label|
      assert_raises(ArgumentError) { Admin::Ui::ButtonComponent.new(label: label, icon: :x) }
    end
  end

  test "an icon button refuses an aria-label of the caller's: its label is its one name" do
    [ { "aria-label": "Other" }, { "aria-label" => "Other" }, { aria: { label: "Other" } }, { aria: { "label" => "Other" } } ].each do |html|
      assert_raises(ArgumentError, html.inspect) { Admin::Ui::ButtonComponent.new(label: "Close", icon: :x, **html) }
    end
    # Without an icon a caller's aria-label passes through, as it always has.
    render_inline Admin::Ui::ButtonComponent.new(label: "⋯", "aria-label": "More")
    assert_equal "More", page.find("button")["aria-label"]
  end

  test "a button without an icon is its label alone, with no tooltip" do
    render_inline Admin::Ui::ButtonComponent.new(label: "Save")

    assert_no_selector "button [data-tooltip]", visible: :all
    assert_nil page.find("button")["aria-label"]
  end
end
