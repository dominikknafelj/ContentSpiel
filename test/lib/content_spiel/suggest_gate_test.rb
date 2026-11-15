require "test_helper"

# `ContentSpiel::SuggestGate`, the middleware in front of the suggestions'
# body (search 2 spec §4.1): it reads `POST /search/suggestions` at most one
# byte past the cap, answers 413 itself, and hands Rails a body that parses,
# so a malformed one is refused from its flag and never quoted by a parse
# error.
class ContentSpiel::SuggestGateTest < ActiveSupport::TestCase
  Gate = ContentSpiel::SuggestGate

  # Records the environment it is called with.
  class App
    attr_reader :env

    def call(env)
      @env = env
      [ 200, {}, [ "next" ] ]
    end
  end

  # An input that counts the bytes it was asked for.
  class CountingInput < StringIO
    attr_reader :asked

    def read(length = nil, *rest)
      @asked = (@asked || 0) + (length || size)
      super
    end
  end

  setup { @app = App.new }

  def call(method: "POST", path: Gate::PATH, body: "", length: :auto, input: nil, **env)
    input ||= StringIO.new(body)
    rack = Rack::MockRequest.env_for(path, method: method, input: input).merge(env)
    rack["CONTENT_LENGTH"] = length == :auto ? body.bytesize.to_s : length
    rack.delete("CONTENT_LENGTH") if rack["CONTENT_LENGTH"].nil?
    Gate.new(@app).call(rack)
  end

  test "the gate leaves every other path and verb alone" do
    big = "x" * 5_000
    [ [ "GET", Gate::PATH ], [ "PUT", Gate::PATH ], [ "POST", "/forms/1" ], [ "POST", "/search" ], [ "POST", "/search/suggestionsx" ] ].each do |method, path|
      status, = call(method: method, path: path, body: big)
      assert_equal 200, status, "#{method} #{path}"
      assert_nil @app.env["content_spiel.suggest.body"], "#{method} #{path}"
      assert_equal big, @app.env["rack.input"].read, "#{method} #{path} keeps its body"
    end
  end

  test "a body with no length is read through at most 1,025 bytes" do
    input = CountingInput.new("{\"suggest\":\"#{"a" * 5_000}\"}")
    status, headers, body = call(input: input, length: nil)

    assert_equal 413, status
    assert_operator input.asked, :<=, Gate::MAX_BODY + 1
    assert_equal "private, no-store", headers["cache-control"]
    assert_equal "noindex", headers["x-robots-tag"]
    assert_equal({ "state" => "refused", "status" => "", "suggestions" => [] }, JSON.parse(body.join))
    assert_nil @app.env, "Rails is not called"
  end

  test "a length over the cap is a 413 with nothing read" do
    input = CountingInput.new("x" * 2_000)
    status, = call(input: input, length: "2000")
    assert_equal 413, status
    assert_nil input.asked
  end

  test "a body at the cap is parsed, handed on as the bytes read, its length set" do
    text = { suggest: "a" * (Gate::MAX_BODY - 14) }.to_json
    assert_equal Gate::MAX_BODY, text.bytesize
    status, = call(body: text, length: nil, "HTTP_TRANSFER_ENCODING" => "chunked")

    assert_equal 200, status
    assert_equal({ "suggest" => "a" * (Gate::MAX_BODY - 14) }, @app.env["content_spiel.suggest.body"])
    assert_equal text, @app.env["rack.input"].read
    assert_equal text.bytesize.to_s, @app.env["CONTENT_LENGTH"]
    assert_nil @app.env["HTTP_TRANSFER_ENCODING"]
  end

  test "malformed JSON is flagged and replaced by {}, its content type kept" do
    call(body: "{\"suggest\": \"secret", "CONTENT_TYPE" => "application/json")
    assert_equal :malformed, @app.env["content_spiel.suggest.body"]
    assert_equal "{}", @app.env["rack.input"].read
    assert_equal "2", @app.env["CONTENT_LENGTH"]
    assert_equal "application/json", @app.env["CONTENT_TYPE"]

    call(body: "\xFF\xFE".b)
    assert_equal :malformed, @app.env["content_spiel.suggest.body"], "bytes that are no UTF-8"
  end
end
