require "test_helper"

# A sample whose declaration matches it: its keyword, a slot, its two keys
# (one of them a plural, which counts as one leaf) and its controller in the
# source the test hands over. Each sample below it gets one thing wrong. The
# samples are named classes, so each has a translation scope of its own
# (`admin.components.ui.ui_contract_sample` and so on), and draw nothing.
class UiContractSampleComponent < Admin::AdminComponent
  include Admin::Ui::Contract

  COMMON = {
    accessibility: "A sample: no role, no name, no keyboard.",
    motion: :none, content_edges: %i[long], widths: :fluid, limits: [ "A test's sample, rendered nowhere." ]
  }.freeze

  renders_one :aside

  contract(states: %i[rest], keys: %w[title count], slots: %i[aside], controller: "admin--ui--dialog",
    script_states: { open: [ "test/system/dialog_test.rb", "a destructive confirm opens on Cancel, Escape backs out, confirming deletes" ] },
    interface: %i[a], **COMMON)

  def initialize(a:)
    @a = a
  end

  def call = ""
end

class UiContractWrongInterfaceComponent < Admin::AdminComponent
  include Admin::Ui::Contract

  contract(states: %i[rest], keys: [], slots: [], controller: nil, interface: %i[b], **UiContractSampleComponent::COMMON)

  def initialize(a:)
    @a = a
  end

  def call = ""
end

class UiContractMissingKeyComponent < Admin::AdminComponent
  include Admin::Ui::Contract

  contract(states: %i[rest], keys: %w[title missing], slots: [], controller: nil, interface: %i[a], **UiContractSampleComponent::COMMON)

  def initialize(a:)
    @a = a
  end

  def call = ""
end

class UiContractSlotLeftOutComponent < Admin::AdminComponent
  include Admin::Ui::Contract

  renders_one :aside

  contract(states: %i[rest], keys: [], slots: [], controller: nil, interface: %i[a], **UiContractSampleComponent::COMMON)

  def initialize(a:)
    @a = a
  end

  def call = ""
end

class UiContractMissingTestComponent < Admin::AdminComponent
  include Admin::Ui::Contract

  contract(states: %i[rest], keys: [], slots: [], controller: nil, interface: %i[a],
    script_states: { open: [ "test/system/dialog_test.rb", "a test this file does not hold" ] }, **UiContractSampleComponent::COMMON)

  def initialize(a:)
    @a = a
  end

  def call = ""
end

class UiContractUndeclaredKeyComponent < Admin::AdminComponent
  include Admin::Ui::Contract

  contract(states: %i[rest], keys: %w[title], slots: [], controller: nil, interface: %i[a], **UiContractSampleComponent::COMMON)

  def initialize(a:)
    @a = a
  end

  def call = ""
end

class UiContractNoControllerFileComponent < Admin::AdminComponent
  include Admin::Ui::Contract

  contract(states: %i[rest], keys: [], slots: [], controller: "contract-sample--no-such-thing", interface: %i[a], **UiContractSampleComponent::COMMON)

  def initialize(a:)
    @a = a
  end

  def call = ""
end

# Every shared component declares its contract (`Admin::Ui::Contract`), and
# the declaration is held to the code: its keywords, its slots, the keys it
# owns, its controller and the browser tests its script-held states name.
class Admin::Ui::ContractTest < ActiveSupport::TestCase
  include UiContract

  setup do
    I18n.backend.store_translations(:en, admin: { components: { ui: {
      ui_contract_sample: { title: "Sample", count: { one: "1 sample", other: "%{count} samples" } },
      ui_contract_missing_key: { title: "Sample" },
      ui_contract_undeclared_key: { title: "Sample", hint: "Unsaid" }
    } } })
  end

  teardown { I18n.reload! }

  def declared = ui_components - UNDECLARED.map(&:constantize)

  test "every Admin::Ui component includes the contract and declares it, but the ones not declared yet" do
    assert_not_empty declared
    declared.each { |klass| assert_contract(klass) }
  end

  test "the undeclared list names only components, and none that declares" do
    names = ui_components.map(&:name)
    UNDECLARED.each do |name|
      assert_includes names, name, "UiContract::UNDECLARED names #{name}, which is no component of app/components/admin/ui"
      assert_nil name.constantize.try(:contract), "#{name} declares its contract: take it out of UiContract::UNDECLARED"
    end
  end

  test "the contract's interface is the component's keywords" do
    declared.each { |klass| assert_contract_interface(klass) }
  end

  test "the contract's slots are the component's slots" do
    declared.each { |klass| assert_contract_slots(klass) }
  end

  test "the contract's keys are the leaves the component owns in ui.en.yml" do
    declared.each { |klass| assert_contract_keys(klass) }
  end

  test "the contract's controller exists and is named in the component's own source" do
    declared.each { |klass| assert_contract_controller(klass) }
  end

  test "a script-held state names a browser test that is there" do
    declared.each { |klass| assert_contract_script_states(klass) }
  end

  test "the contract can fail" do
    source = 'data-controller="admin--ui--dialog"'
    assert_contract(UiContractSampleComponent, source: source)

    failure = assert_raises(Minitest::Assertion) { assert_contract(UiContractWrongInterfaceComponent, source: "") }
    assert_match "interface", failure.message

    failure = assert_raises(Minitest::Assertion) { assert_contract(UiContractMissingKeyComponent, source: "") }
    assert_match "keys", failure.message
    assert_match "missing", failure.message

    failure = assert_raises(Minitest::Assertion) { assert_contract(UiContractSlotLeftOutComponent, source: "") }
    assert_match "slots", failure.message

    failure = assert_raises(Minitest::Assertion) { assert_contract(UiContractMissingTestComponent, source: "") }
    assert_match "script_states", failure.message
    assert_match "a test this file does not hold", failure.message

    failure = assert_raises(Minitest::Assertion) { assert_contract(UiContractUndeclaredKeyComponent, source: "") }
    assert_match "keys leave them out", failure.message
    assert_match "hint", failure.message

    failure = assert_raises(Minitest::Assertion) { assert_contract(UiContractNoControllerFileComponent, source: "contract-sample--no-such-thing") }
    assert_match "has no file", failure.message

    failure = assert_raises(Minitest::Assertion) { assert_contract(UiContractSampleComponent, source: "") }
    assert_match "controller", failure.message

    failure = assert_raises(Minitest::Assertion) { assert_contract_interface(Class.new { def self.name = "UiContractBareComponent" }) }
    assert_match "UiContractBareComponent", failure.message
  end

  # A component's own file names its controller only in its declaration and a
  # comment: the check reads its source the way it reads a real component's,
  # from the file, and still fails.
  test "the controller check reads a component's file around its declaration and comments" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "ui_contract_from_file_component.rb")
      File.write(path, <<~RUBY)
        # Stands on admin--ui--dialog, says this comment.
        class UiContractFromFileComponent < Admin::AdminComponent
          include Admin::Ui::Contract

          contract(states: %i[rest], keys: [], slots: [], controller: "admin--ui--dialog", interface: %i[a],
            **UiContractSampleComponent::COMMON)

          def initialize(a:)
            @a = a
          end

          def call = ""
        end
      RUBY
      load path
      failure = assert_raises(Minitest::Assertion) { assert_contract(UiContractFromFileComponent) }
      assert_match "not named in its own source", failure.message

      File.write(path.sub(/\.rb\z/, ".html.erb"), %(<div data-controller="admin--ui--dialog"></div>))
      assert_contract(UiContractFromFileComponent)
    ensure
      Object.send(:remove_const, :UiContractFromFileComponent) if Object.const_defined?(:UiContractFromFileComponent, false)
    end
  end

  test "a state both drawn and held by a script is refused when the class declares" do
    error = assert_raises(ArgumentError) do
      Class.new(Admin::AdminComponent) do
        def self.name = "UiContractBothComponent"
        include Admin::Ui::Contract
        contract(states: %i[rest open], keys: [], slots: [], controller: nil, interface: [],
          script_states: { open: [ "test/system/dialog_test.rb", "x" ] }, **UiContractSampleComponent::COMMON)
      end
    end
    assert_match "UiContractBothComponent", error.message
    assert_match "script_states", error.message
  end
end
