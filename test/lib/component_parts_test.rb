require "test_helper"

# A component made after the contract, for "each part guard can fail": it
# declares no keyboard test and is on no list. It is named outside
# `Admin::Ui`, so no guard but the sample's reads it, and draws nothing.
class ComponentPartsMadeAfterSampleComponent < Admin::AdminComponent
  include Admin::Ui::Contract

  contract(accessibility: "A sample: no role, no name, no keyboard.", motion: :none, content_edges: %i[short], widths: :fluid,
    limits: [ "A test's sample, rendered nowhere." ], interface: [], states: %i[rest], keys: [], slots: [], controller: nil)

  def call = ""
end

# THE PART GUARDS. A shared CS Studio component (`app/components/admin/ui/`)
# comes with its parts: a component test, a Lookbook preview with an example
# of each state a static render draws, and a card in the Design System
# artifact (test/support/design_system_entries.rb). One made after the
# contract names its keyboard browser test too. The components are derived
# from the files (`UiContract#ui_components`), so a new one meets every guard
# from the day its file is written.
#
# Each guard is a matcher that answers what is missing or stale, run over the
# real components and lists, and, in "each part guard can fail", over a
# sample.
class ComponentPartsTest < ActiveSupport::TestCase
  include UiContract

  ROOT = Rails.root

  # The components among `names` that have no test at
  # test/components/admin/ui/<name>_test.rb.
  def self.without_test(names)
    names.reject { |name| ROOT.join("test/components/admin/ui/#{name.demodulize.underscore}_test.rb").exist? }
  end

  # The states a component declares that its preview has no example of: the
  # pointer and keyboard states are drawn by the browser, and the script-held
  # ones are not in `states:` at all.
  def self.missing_examples(states, examples)
    (states - Admin::Ui::Contract::STATES_NOT_PREVIEWED) - examples.map(&:to_sym)
  end

  # The components among `names` with no card and no reason.
  def self.without_entry(names)
    names.reject { |name| DesignSystemEntries.entry_for(name) || DesignSystemEntries::NOT_YET.key?(name) }
  end

  # What the entries' lists name that matches nothing: a component that is
  # not one, a card that is not in `entries`, a mapping the component's own
  # name already gives, and a reason for a component that has a card.
  def self.stale_entries(names, covered_by: DesignSystemEntries::COVERED_BY, not_yet: DesignSystemEntries::NOT_YET, entries: DesignSystemEntries::ENTRIES)
    [
      *((covered_by.keys + not_yet.keys) - names).map { |name| "#{name} is not a component in app/components/admin/ui/" },
      *(covered_by.values.uniq - entries).map { |card| "#{card} is not a card in ENTRIES" },
      *covered_by.select { |name, card| DesignSystemEntries.own_name(name) == card }.keys.map { |name| "#{name} is mapped to the card of its own name" },
      *not_yet.keys.select { |name| covered_by.key?(name) || entries.include?(DesignSystemEntries.own_name(name)) }.map { |name| "#{name} has a card and a NOT_YET reason" }
    ]
  end

  # The components among `components` made after the contract that name no
  # keyboard test and are not let through by `not_yet`.
  def self.without_keyboard(components, made_before: MADE_BEFORE_CONTRACT, not_yet: KEYBOARD_NOT_YET)
    components.reject { |klass| made_before.include?(klass.name) || not_yet.key?(klass.name) || klass.contract.keyboard }.map(&:name)
  end

  # What a list of components (`MADE_BEFORE_CONTRACT`, `KEYBOARD_NOT_YET`)
  # names that is not a component, or that declares its keyboard test and so
  # has left the list's reason behind.
  def self.stale_keyboard_list(listed, names)
    [
      *(listed - names).map { |name| "#{name} is not a component in app/components/admin/ui/" },
      *(listed & names).select { |name| name.constantize.contract.keyboard }.map { |name| "#{name} declares its keyboard test" }
    ]
  end

  def names = ui_components.map(&:name)

  test "every Admin::Ui component has a component test" do
    assert_empty self.class.without_test(names), "these shared components have no test/components/admin/ui/<name>_test.rb"
  end

  test "every Admin::Ui component's preview has an example for each previewable state it declares" do
    previews = ViewComponent::Preview.all.index_by(&:name)
    problems = ui_components.filter_map do |klass|
      preview = previews["#{klass.name}Preview"] or next "#{klass.name} has no preview (#{klass.name}Preview in test/components/previews/admin/ui/)"
      missing = self.class.missing_examples(klass.contract.states, preview.examples)
      "#{preview.name} has no example of #{missing.join(', ')}" if missing.any?
    end
    assert_empty problems, "a shared component's preview draws each state of `states:` (but hover, focus and pressed) as an example of the same name"
  end

  test "every Admin::Ui component has a Design System entry, or is listed with the reason it has none" do
    assert_empty self.class.without_entry(names),
      "these shared components have no card in the Design System (DesignSystemEntries::ENTRIES), no COVERED_BY card and no NOT_YET reason"
  end

  test "the entries' lists name only components and entries" do
    assert_empty self.class.stale_entries(names), "test/support/design_system_entries.rb names what matches nothing"
  end

  test "a shared component made after the contract names its keyboard browser test, and the test is there" do
    assert_empty self.class.without_keyboard(ui_components),
      "a shared component made after the contract declares `keyboard:`, or waits in UiContract::KEYBOARD_NOT_YET with its reason"
    ui_components.each { |klass| assert_contract_keyboard(klass) }
  end

  test "the keyboard not-yet list names only components that declare no keyboard test" do
    assert_empty self.class.stale_keyboard_list(KEYBOARD_NOT_YET.keys, names), "UiContract::KEYBOARD_NOT_YET names what it should not"
    assert_empty KEYBOARD_NOT_YET.keys & MADE_BEFORE_CONTRACT, "UiContract::KEYBOARD_NOT_YET names components made before the contract"
  end

  test "the made-before list names only components" do
    assert_empty self.class.stale_keyboard_list(MADE_BEFORE_CONTRACT, names),
      "UiContract::MADE_BEFORE_CONTRACT names what it should not: it only shrinks, so a component that declares its keyboard test leaves it"
  end

  test "each part guard can fail" do
    missing = "Admin::Ui::NoSuchThingComponent"
    sample = ComponentPartsMadeAfterSampleComponent

    assert_equal [ missing ], self.class.without_test([ "Admin::Ui::ButtonComponent", missing ])

    assert_equal %i[disabled], self.class.missing_examples(%i[rest hover focus pressed disabled], %w[rest])
    assert_empty self.class.missing_examples(%i[rest hover focus], %w[rest])

    assert_equal [ missing ], self.class.without_entry([ "Admin::Ui::ButtonComponent", missing ])
    assert_equal "Button", DesignSystemEntries.entry_for(Admin::Ui::ButtonComponent)
    assert_equal "Badge", DesignSystemEntries.entry_for(Admin::Ui::StatusChipComponent)
    stale = self.class.stale_entries(names,
      covered_by: { missing => "Badge", "Admin::Ui::BadgeComponent" => "Badge", "Admin::Ui::MenuComponent" => "NoSuchCard" },
      not_yet: { "Admin::Ui::ButtonComponent" => "a reason" })
    assert_equal [ "#{missing} is not a component in app/components/admin/ui/", "NoSuchCard is not a card in ENTRIES",
                   "Admin::Ui::BadgeComponent is mapped to the card of its own name", "Admin::Ui::ButtonComponent has a card and a NOT_YET reason" ], stale

    assert_equal [ sample.name ], self.class.without_keyboard([ sample, Admin::Ui::ButtonComponent, Admin::Ui::MenuComponent ])
    assert_empty self.class.without_keyboard([ sample ], not_yet: { sample.name => "its test comes later" })
    assert_equal [ "#{missing} is not a component in app/components/admin/ui/", "Admin::Ui::MenuComponent declares its keyboard test" ],
      self.class.stale_keyboard_list([ missing, "Admin::Ui::MenuComponent", "Admin::Ui::ButtonComponent" ], names)
  end
end
