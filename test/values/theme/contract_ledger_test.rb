require "test_helper"

# The built-in types' part of the contract is the ledger
# (test/support/contract_ledger.rb, which says why it is written by hand).
class Theme::ContractLedgerTest < ActiveSupport::TestCase
  include ContractLedger

  def outside = BlockTypes.all.select(&:owner)

  def built_in_components
    Theme::Contract.components.except(*outside.filter_map { |definition| definition.component && Theme::Contract.path_of(definition.component) })
  end

  def built_in(list, reader) = list - outside.flat_map(&reader)

  def assert_ledger(components: built_in_components, themed: built_in(Theme::Contract.themed_tokens, :themed_tokens), fixed: built_in(Theme::Contract.fixed_tokens, :fixed_tokens))
    note = "Theme::Contract no longer says what the ledger says. A theme outside this repository relies on every name here: " \
           "if the change is meant, write the release note and change the ledger in test/support/contract_ledger.rb with it"
    assert_equal COMPONENTS.keys, components.keys, "#{note} (the components, in order)"
    COMPONENTS.each { |path, methods| assert_equal methods, components.fetch(path), "#{note} (the methods of #{path})" }
    assert_equal THEMED_TOKENS, themed, "#{note} (the themed tokens, in order)"
    assert_equal FIXED_TOKENS, fixed, "#{note} (the fixed tokens, in order)"
  end

  test "the built-in types' part of the contract is the ledger: a name added, renamed or removed is a release note" do
    assert_ledger
  end

  test "the ledger can fail: a method dropped from a built-in's line, and a token renamed, are each named" do
    dropped = built_in_components.merge("blocks/image_component" => %w[block page asset alt caption])
    error = assert_raises(Minitest::Assertion) { assert_ledger(components: dropped) }
    assert_includes error.message, "the methods of blocks/image_component"

    renamed = built_in(Theme::Contract.themed_tokens, :themed_tokens).map { |name| name == "syn-attribute" ? "syn-attr" : name }
    error = assert_raises(Minitest::Assertion) { assert_ledger(themed: renamed) }
    assert_includes error.message, "the themed tokens, in order"
  end
end
