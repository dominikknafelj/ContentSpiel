require "test_helper"

# Translation helpers spec §6.2: AI is configured when there's a provider,
# a registered class for it and a key; `AI.provider` builds that class from
# the site settings, the model defaulting to `claude-sonnet-5`.
class AITest < ActiveSupport::TestCase
  teardown { Rails.application.reloader.prepare! }

  class RecordingProvider
    attr_reader :api_key, :model

    def initialize(api_key:, model:)
      @api_key = api_key
      @model = model
    end
  end

  setup do
    AI::Providers.register("test/recording", RecordingProvider)
    @site = Current.site
  end

  test "configured only with a provider, a registered class and a key" do
    assert_not AI.configured?

    @site.update!(ai_provider: "test/recording")
    assert_not AI.configured?, "no key"

    @site.update!(ai_api_key: "sk-test")
    assert AI.configured?

    # Written around the model: saving it through `update!` is refused
    # (`SiteSetting#ai_provider_is_registered`), but a provider whose
    # plugin was removed later stays stored.
    @site.update_column(:ai_provider, "gone/provider")
    Current.site = nil # no commit callback to drop the cached row this time
    assert_not AI.configured?, "an unregistered provider"

    @site.update!(ai_provider: nil)
    assert_not AI.configured?
  end

  test "provider is built from the settings, with the default model when none is set" do
    @site.update!(ai_provider: "test/recording", ai_api_key: "sk-test")

    provider = AI.provider
    assert_instance_of RecordingProvider, provider
    assert_equal "sk-test", provider.api_key
    assert_equal "claude-sonnet-5", provider.model

    @site.update!(ai_model: "claude-opus-5")
    assert_equal "claude-opus-5", AI.provider.model
  end

  test "provider raises AI::Error when AI isn't configured" do
    error = assert_raises(AI::Error) { AI.provider }
    assert_match(/Settings/, error.message)
  end
end
