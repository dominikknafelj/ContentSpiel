require "test_helper"

# The built-in types' part of the contract is the ledger
# (test/support/contract_ledger.rb, which says why it is written by hand).
class Theme::ContractLedgerTest < ActiveSupport::TestCase
  include ContractLedger

  def outside = BlockTypes.all.select(&:owner)

  # A gem's form field type's own input is its gem's promise too.
  def outside_inputs
    built_in = Forms::FieldTypes.all.reject { |type| type.name.include?("/") }.map(&:input)
    Forms::FieldTypes.all.select { |type| type.name.include?("/") }.map(&:input) - built_in
  end

  def built_in_components
    paths = outside.filter_map { |definition| definition.component && Theme::Contract.path_of(definition.component) } +
      outside_inputs.map { |input| Theme::Contract.path_of(input) }
    Theme::Contract.components.except(*paths)
  end

  def built_in(list, reader) = list - outside.flat_map(&reader)

  def assert_ledger(components: built_in_components, themed: built_in(Theme::Contract.themed_tokens, :themed_tokens), fixed: built_in(Theme::Contract.fixed_tokens, :fixed_tokens), classes: Theme::Contract.classes, attributes: Theme::Contract.attributes)
    note = "Theme::Contract no longer says what the ledger says. A theme outside this repository relies on every name here: " \
           "if the change is meant, write the release note and change the ledger in test/support/contract_ledger.rb with it"
    assert_equal COMPONENTS.keys, components.keys, "#{note} (the components, in order)"
    COMPONENTS.each { |path, methods| assert_equal methods, components.fetch(path), "#{note} (the methods of #{path})" }
    assert_equal CLASSES, classes, "#{note} (the classes)"
    assert_equal ATTRIBUTES, attributes, "#{note} (the attributes)"
    assert_equal THEMED_TOKENS, themed, "#{note} (the themed tokens, in order)"
    assert_equal FIXED_TOKENS, fixed, "#{note} (the fixed tokens, in order)"
  end

  test "the built-in types' part of the contract is the ledger: a name added, renamed or removed is a release note" do
    assert_ledger
  end

  test "the page templates' locals are the ledger's" do
    assert_equal PAGE_TEMPLATE_LOCALS, Theme::Contract::PAGE_TEMPLATE_LOCALS, "a local a page template is handed added, renamed or removed is a release note"
    assert_equal PAGE_TEMPLATES, Theme::Contract::PAGE_TEMPLATES
  end

  test "the ledger can fail: a method dropped from a built-in's line, and a token renamed, are each named" do
    # The ledger's own components, so a built-in added since (the moment the
    # test above goes red) does not make this one red too, with a message
    # that says nothing about why.
    ledgered = built_in_components.slice(*COMPONENTS.keys)
    dropped = ledgered.merge("blocks/image_component" => %w[block page asset alt caption])
    error = assert_raises(Minitest::Assertion) { assert_ledger(components: dropped) }
    assert_includes error.message, "the methods of blocks/image_component"

    renamed = built_in(Theme::Contract.themed_tokens, :themed_tokens).map { |name| name == "syn-attribute" ? "syn-attr" : name }
    error = assert_raises(Minitest::Assertion) { assert_ledger(components: ledgered, themed: renamed) }
    assert_includes error.message, "the themed tokens, in order"
  end

  test "the default theme's icon names are the ledger's" do
    assert_equal DEFAULT_ICONS, Theme::Declarations.default["icons"].map(&:name), "an icon name added, renamed or removed is a release note"
  end
end
