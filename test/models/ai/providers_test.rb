require "test_helper"

# Translation helpers spec §6.1: the provider registry -- built-in names
# bare, plugin names `owner/name` (the same shape rule as `ContentModel::
# Registry`), a duplicate raising `AI::DuplicateProvider`.
class AI::ProvidersTest < ActiveSupport::TestCase
  teardown { Rails.application.reloader.prepare! }

  class FakeProvider; end

  test "the built-in anthropic provider is registered" do
    assert_equal AI::Providers::Anthropic, AI::Providers.find("anthropic")
    assert_includes AI::Providers.names, "anthropic"
  end

  test "register, then find by name; an unknown name finds nothing" do
    AI::Providers.register("acme/llm", FakeProvider)

    assert_equal FakeProvider, AI::Providers.find("acme/llm")
    assert_equal FakeProvider, AI::Providers.find(:"acme/llm")
    assert_nil AI::Providers.find("nope")
    assert_nil AI::Providers.find(nil)
    assert_equal %w[anthropic acme/llm], AI::Providers.names
  end

  test "a duplicate name raises" do
    assert_raises(AI::DuplicateProvider) { AI::Providers.register("anthropic", FakeProvider) }
  end

  test "names must be bare lowercase words or owner/name" do
    [ "Bad Name", "acme/", "/llm", "acme/llm/extra", "Acme/llm", "" ].each do |name|
      assert_raises(ArgumentError, name) { AI::Providers.register(name, FakeProvider) }
    end
  end

  test "reset! empties the registry" do
    AI::Providers.reset!

    assert_empty AI::Providers.names
    assert_nil AI::Providers.find("anthropic")
  end
end
