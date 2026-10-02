require "test_helper"

# Translation helpers spec §6.1: the built-in provider, against a fake
# client -- these tests never reach the network. The fake stands in for
# `Anthropic::Client`: `messages.create(**params)` records the request and
# answers with whatever the test queued (a Message-shaped reply or an SDK
# error to raise).
class AI::Providers::AnthropicTest < ActiveSupport::TestCase
  TextBlock = Struct.new(:type, :text, keyword_init: true)
  Reply = Struct.new(:content, :stop_reason, keyword_init: true)

  class FakeClient
    attr_reader :requests

    def initialize(answer)
      @answer = answer
      @requests = []
    end

    def messages = self

    def create(params)
      @requests << params
      raise @answer if @answer.is_a?(Exception)

      @answer
    end
  end

  def reply(text, stop_reason: :end_turn) = Reply.new(content: [ TextBlock.new(type: :text, text: text) ], stop_reason: stop_reason)

  def provider_with(answer, model: "claude-sonnet-5")
    @client = FakeClient.new(answer)
    AI::Providers::Anthropic.new(api_key: "sk-test", model: model, client: @client)
  end

  def request = @client.requests.last

  def sdk_error(klass, status)
    klass.new(url: URI("https://api.anthropic.com/v1/messages"), status: status, headers: {}, body: nil, request: nil, response: nil)
  end

  test "the request carries the model, both language names and the numbered texts" do
    provider = provider_with(reply("<<<1>>>\nHallo\n<<<2>>>\nWelt"))

    provider.translate(texts: [ "Hello", "World" ], from: "en", to: "de", format: :plain)

    assert_equal "claude-sonnet-5", request[:model]
    assert_operator request[:max_tokens], :>, 0
    assert_includes request[:system], "English"
    assert_includes request[:system], "German"
    assert_equal 1, request[:messages].size
    assert_equal "user", request[:messages].first[:role]
    assert_equal "<<<1>>>\nHello\n<<<2>>>\nWorld", request[:messages].first[:content]
  end

  test "the model named in the settings is the one asked" do
    provider = provider_with(reply("<<<1>>>\nHallo"), model: "claude-opus-5")
    provider.translate(texts: [ "Hello" ], from: "en", to: "de", format: :plain)

    assert_equal "claude-opus-5", request[:model]
  end

  test "the response is parsed back into one translation per text, in order" do
    answer = "<<<1>>>\nHallo\n\n<<<2>>>\nZwei Zeilen\nhier\n<<<3>>>\nWelt\n"
    provider = provider_with(reply(answer))

    assert_equal [ "Hallo", "Zwei Zeilen\nhier", "Welt" ],
      provider.translate(texts: %w[Hello Two World], from: "en", to: "de", format: :plain)
  end

  test "only surrounding newlines are trimmed, so indentation survives" do
    answer = "<<<1>>>\n    code()\n  - nested\n\n<<<2>>>\nWelt\n"
    provider = provider_with(reply(answer))

    assert_equal [ "    code()\n  - nested", "Welt" ],
      provider.translate(texts: [ "    code()\n  - nested", "World" ], from: "en", to: "de", format: :markdown)
  end

  test "an empty translation of a non-empty text raises AI::Error" do
    provider = provider_with(reply("<<<1>>>\n\n<<<2>>>\nWelt"))

    error = assert_raises(AI::Error) { provider.translate(texts: %w[Hello World], from: "en", to: "de", format: :plain) }
    assert_match(/empty translation/, error.message)
  end

  test "text split across several content blocks is read as one answer" do
    answer = Reply.new(content: [ TextBlock.new(type: :text, text: "<<<1>>>\nHal"), TextBlock.new(type: :text, text: "lo") ], stop_reason: :end_turn)

    assert_equal [ "Hallo" ], provider_with(answer).translate(texts: [ "Hello" ], from: "en", to: "de", format: :plain)
  end

  test "a count mismatch raises AI::Error" do
    provider = provider_with(reply("<<<1>>>\nHallo"))

    assert_raises(AI::Error) { provider.translate(texts: %w[Hello World], from: "en", to: "de", format: :plain) }
  end

  test "markers out of order or with no marker at all raise AI::Error" do
    assert_raises(AI::Error) do
      provider_with(reply("<<<2>>>\nWelt\n<<<1>>>\nHallo")).translate(texts: %w[Hello World], from: "en", to: "de", format: :plain)
    end
    assert_raises(AI::Error) do
      provider_with(reply("Hallo")).translate(texts: [ "Hello" ], from: "en", to: "de", format: :plain)
    end
  end

  test "an answer cut off at the token limit raises AI::Error saying so" do
    provider = provider_with(reply("<<<1>>>\nHallo", stop_reason: :max_tokens))

    error = assert_raises(AI::Error) { provider.translate(texts: [ "Hello" ], from: "en", to: "de", format: :plain) }
    assert_match(/in parts/, error.message)
  end

  test "a text that itself contains a marker line is refused before anything is sent" do
    provider = provider_with(reply("<<<1>>>\nx"))

    assert_raises(AI::Error) { provider.translate(texts: [ "a\n<<<1>>>\nb" ], from: "en", to: "de", format: :plain) }
    assert_empty @client.requests
  end

  test "the markdown format tells the model to keep directives and cs: links" do
    provider = provider_with(reply("<<<1>>>\n**Hallo**"))
    provider.translate(texts: [ "**Hello**" ], from: "en", to: "de", format: :markdown)

    assert_includes request[:system], "::"
    assert_includes request[:system], "cs:"
    assert_includes request[:system], "Markdown"
  end

  test "the plain format says nothing about Markdown" do
    provider_with(reply("<<<1>>>\nHallo")).translate(texts: [ "Hello" ], from: "en", to: "de", format: :plain)

    assert_not_includes request[:system], "Markdown"
  end

  test "an unknown format is an ArgumentError" do
    assert_raises(ArgumentError) { provider_with(reply("")).translate(texts: [ "x" ], from: "en", to: "de", format: :html) }
  end

  test "SDK errors become AI::Error with a clear message" do
    {
      sdk_error(Anthropic::Errors::AuthenticationError, 401) => /API key/,
      sdk_error(Anthropic::Errors::PermissionDeniedError, 403) => /API key/,
      sdk_error(Anthropic::Errors::RateLimitError, 429) => /rate limit/i,
      sdk_error(Anthropic::Errors::InternalServerError, 529) => /busy/,
      sdk_error(Anthropic::Errors::NotFoundError, 404) => /model/,
      sdk_error(Anthropic::Errors::BadRequestError, 400) => /refused/,
      Anthropic::Errors::APITimeoutError.new(url: URI("https://api.anthropic.com")) => /in time/,
      Anthropic::Errors::APIConnectionError.new(url: URI("https://api.anthropic.com")) => /reach/
    }.each do |sdk_error, message|
      error = assert_raises(AI::Error, sdk_error.class.name) do
        provider_with(sdk_error).translate(texts: [ "Hello" ], from: "en", to: "de", format: :plain)
      end
      assert_match message, error.message, sdk_error.class.name
      assert_not_includes error.message, "sk-test"
    end
  end

  test "test_connection sends a tiny request and answers true" do
    assert_equal true, provider_with(reply("ok")).test_connection
    assert_equal "claude-sonnet-5", request[:model]
    assert_operator request[:max_tokens], :<=, 16
  end

  test "test_connection raises the mapped AI::Error" do
    error = assert_raises(AI::Error) { provider_with(sdk_error(Anthropic::Errors::AuthenticationError, 401)).test_connection }
    assert_match(/API key/, error.message)
  end

  test "without an injected client it builds the SDK client with the key and a 25 second timeout" do
    provider = AI::Providers::Anthropic.new(api_key: "sk-test", model: "claude-sonnet-5")
    client = provider.instance_variable_get(:@client)

    assert_instance_of Anthropic::Client, client
    assert_equal "sk-test", client.api_key
    assert_equal 25, client.timeout
  end

  # Final fix wave, I2: a suggestion request runs inside an editor's web
  # request, behind kamal-proxy (default response timeout 30 s). One
  # `AI::Translate` call makes at most two provider calls (plain fields,
  # then rich text), each bounded by `TIMEOUT`, so the proxy's timeout in
  # config/deploy.yml must outlast both -- or the proxy cuts the request
  # off while Puma is still waiting on the provider.
  test "the production proxy waits longer than one suggestion request can take" do
    deploy = YAML.load_file(Rails.root.join("config/deploy.yml"))
    response_timeout = deploy.dig("proxy", "response_timeout")

    assert_kind_of Integer, response_timeout, "config/deploy.yml sets no proxy response_timeout (kamal-proxy's default is 30 s)"
    assert_operator response_timeout, :>, 2 * AI::Providers::Anthropic::TIMEOUT
  end

  test "a blank key is refused rather than falling back to the server's environment" do
    assert_raises(AI::Error) { AI::Providers::Anthropic.new(api_key: "", model: "claude-sonnet-5") }
  end
end
