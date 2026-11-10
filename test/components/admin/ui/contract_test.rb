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

  test "every Admin::Ui component includes the contract and declares it" do
    assert_operator ui_components.size, :>=, 44
    assert ui_components.none? { it.include?(Blocks::Contract) }, "a shared component includes one contract, CS Studio's"
    ui_components.each { |klass| assert_contract(klass) }
  end

  test "the contract's interface is the component's keywords" do
    assert_operator ui_components.size, :>=, 44
    ui_components.each { |klass| assert_contract_interface(klass) }
  end

  test "the contract's slots are the component's slots" do
    assert_operator ui_components.size, :>=, 44
    ui_components.each { |klass| assert_contract_slots(klass) }
  end

  test "the contract's keys are the leaves the component owns in ui.en.yml" do
    assert_operator ui_components.size, :>=, 44
    ui_components.each { |klass| assert_contract_keys(klass) }
  end

  test "the contract's controller exists and is named in the component's own source" do
    assert_operator ui_components.size, :>=, 44
    ui_components.each { |klass| assert_contract_controller(klass) }
  end

  test "a script-held state names a browser test that is there" do
    assert_operator ui_components.size, :>=, 44
    ui_components.each { |klass| assert_contract_script_states(klass) }
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

    # One of two controllers a `controller:` key attaches is attached.
    assert_contract(UiContractSampleComponent, source: 'data: { controller: "admin--ui--dialog admin--media--select" }')

    # A target and an action of the controller are not its attachment.
    serves = 'data-admin--ui--dialog-target="panel" data-action="click->admin--ui--dialog#open"'
    failure = assert_raises(Minitest::Assertion) { assert_contract(UiContractSampleComponent, source: serves) }
    assert_match "not attached in its own markup", failure.message

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
      assert_match "not attached in its own markup", failure.message

      File.write(path.sub(/\.rb\z/, ".html.erb"), %(<div data-controller="admin--ui--dialog"></div>))
      assert_contract(UiContractFromFileComponent)
    ensure
      Object.send(:remove_const, :UiContractFromFileComponent) if Object.const_defined?(:UiContractFromFileComponent, false)
    end
  end

  # A component with no template (`Admin::Ui::RailPanelComponent`) names its
  # controller in its Ruby code alone, and the check reads that code's text.
  test "the controller check reads a component's Ruby code, with no template beside it" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "ui_contract_from_code_component.rb")
      File.write(path, <<~RUBY)
        class UiContractFromCodeComponent < Admin::AdminComponent
          include Admin::Ui::Contract

          contract(states: %i[rest], keys: [], slots: [], controller: "admin--ui--dialog", interface: %i[a],
            **UiContractSampleComponent::COMMON)

          def initialize(a:)
            @a = a
          end

          def call = tag.div(data: { controller: "admin--ui--dialog" })
        end
      RUBY
      load path
      assert_contract(UiContractFromCodeComponent)
    ensure
      Object.send(:remove_const, :UiContractFromCodeComponent) if Object.const_defined?(:UiContractFromCodeComponent, false)
    end
  end

  test "a class that includes both contracts is refused" do
    both = ->(first, second) { Class.new(ViewComponent::Base) { include first; include second } }
    assert_raises(ArgumentError) { both.(Admin::Ui::Contract, Blocks::Contract) }
    assert_raises(ArgumentError) { both.(Blocks::Contract, Admin::Ui::Contract) }
  end

  # A component that takes no focus says so in a sentence, which names no
  # test; anything but a test's [file, name], a sentence or nil is refused.
  test "a keyboard is a browser test or the sentence that it takes no focus, and anything else is refused when the class declares" do
    declare = lambda do |keyboard|
      Class.new(Admin::AdminComponent) do
        def self.name = "UiContractKeyboardComponent"
        include Admin::Ui::Contract
        contract(states: %i[rest], keys: [], slots: [], controller: nil, interface: [], keyboard: keyboard, **UiContractSampleComponent::COMMON)
      end
    end

    sentence = declare.("It takes no focus: a word beside its row's link.")
    assert_equal "It takes no focus: a word beside its row's link.", sentence.contract.keyboard
    assert_contract_keyboard(sentence)

    [ "", "  ", [ "test/system/dialog_test.rb" ], :none ].each do |keyboard|
      error = assert_raises(ArgumentError) { declare.(keyboard) }
      assert_match "UiContractKeyboardComponent's contract: keyboard", error.message
    end

    missing = declare.([ "test/system/dialog_test.rb", "a test this file does not hold" ])
    failure = assert_raises(Minitest::Assertion) { assert_contract_keyboard(missing) }
    assert_match "a test this file does not hold", failure.message
  end

  # A sentence is allowed only to a component whose markup draws nothing that
  # can take the focus: the check reads its own files, the components it
  # renders by name, and refuses what it cannot read but a slot its sentence
  # names. The samples are written to files, as the check reads a file.
  test "a keyboard sentence is refused on a component that draws what can take the focus, or that the check cannot read" do
    Dir.mktmpdir do |dir|
      write = lambda do |name, body, sentence|
        File.write(File.join(dir, "#{name.underscore}.rb"), <<~RUBY)
          class #{name} < Admin::AdminComponent
            include Admin::Ui::Contract

            #{body}

            contract(states: %i[rest], keys: [], slots: [], controller: nil, interface: [],
              keyboard: #{sentence.inspect}, **UiContractSampleComponent::COMMON)

            def call = ""
          end
        RUBY
        load File.join(dir, "#{name.underscore}.rb")
        name.constantize
      end

      quiet = write.("UiContractQuietComponent", "def drawn = tag.span(\"x\")", "It takes no focus: a word.")
      assert_contract_keyboard(quiet)

      button = write.("UiContractButtonComponent", "def drawn = tag.button(\"x\")", "It takes no focus: a word.")
      failure = assert_raises(Minitest::Assertion) { assert_contract_keyboard(button) }
      assert_match "UiContractButtonComponent draws a control", failure.message

      toasts = write.("UiContractToastsComponent", "def drawn = render(Admin::Ui::ToastComponent.new(message: \"x\"))", "It takes no focus: a region.")
      failure = assert_raises(Minitest::Assertion) { assert_contract_keyboard(toasts) }
      assert_match "Admin::Ui::ToastComponent draws a control", failure.message

      entries = write.("UiContractEntriesComponent", "def drawn = render(entry.component.new)", "It takes no focus: a slot.")
      failure = assert_raises(Minitest::Assertion) { assert_contract_keyboard(entries) }
      assert_match "a render of entry.component.new", failure.message

      unnamed = write.("UiContractUnnamedSlotComponent", "renders_one :aside", "It takes no focus: a word.")
      failure = assert_raises(Minitest::Assertion) { assert_contract_keyboard(unnamed) }
      assert_match "the slot aside", failure.message

      named = write.("UiContractNamedSlotComponent", "renders_one :aside", "It takes no focus: a word, and the `aside` a caller hands it is a word too.")
      assert_contract_keyboard(named)

      # A slot is named as a word: "beside" does not name `aside`.
      inside = write.("UiContractInsideWordComponent", "renders_one :aside", "It takes no focus: a word beside a link.")
      failure = assert_raises(Minitest::Assertion) { assert_contract_keyboard(inside) }
      assert_match "the slot aside", failure.message

      # The string "content" (the CS Studio frame's name) is no block handed over.
      frame = write.("UiContractFrameNameComponent", "def drawn = tag.span(\"x\", data: { turbo_frame: \"content\" })", "It takes no focus: a word.")
      assert_contract_keyboard(frame)

      # A component it renders by name passes up what that one cannot read.
      slot = write.("UiContractRendersSlotComponent", "def drawn = render(Admin::Ui::SlotComponent.new(name: \"x\", record: nil, viewer: nil))", "It takes no focus: a word.")
      failure = assert_raises(Minitest::Assertion) { assert_contract_keyboard(slot) }
      assert_match "Admin::Ui::SlotComponent's a render of entry.component.new", failure.message

      # Each of HTML's other focusable shapes is refused.
      {
        "Summary" => [ "def drawn = tag.details(tag.summary(\"x\"))", "draws a summary" ],
        "EmailField" => [ "def drawn = email_field_tag(:x)", "draws a control" ],
        "SearchField" => [ "def drawn = search_field_tag(:x)", "draws a control" ],
        "FormBuilder" => [ "def drawn = form_with(url: \"/x\") { |f| f.text_field(:x) }", "draws a form" ],
        "Frame" => [ "def drawn = tag.iframe(src: \"/x\")", "draws a frame" ],
        "Video" => [ "def drawn = tag.video(src: \"/x\", controls: true)", "draws a media control" ],
        "Area" => [ "def drawn = tag.area(href: \"/x\")", "draws a link" ]
      }.each do |part, (body, said)|
        component = write.("UiContract#{part}ShapeComponent", body, "It takes no focus: a word.")
        failure = assert_raises(Minitest::Assertion, part) { assert_contract_keyboard(component) }
        assert_match "UiContract#{part}ShapeComponent #{said}", failure.message
      end
    ensure
      %w[Quiet Button Toasts Entries UnnamedSlot NamedSlot InsideWord FrameName RendersSlot
         SummaryShape EmailFieldShape SearchFieldShape FormBuilderShape FrameShape VideoShape AreaShape].each do |part|
        name = "UiContract#{part}Component"
        Object.send(:remove_const, name) if Object.const_defined?(name, false)
      end
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
