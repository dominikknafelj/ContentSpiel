require "test_helper"

class Admin::TokensScreen::ConnectStepComponentTest < ViewComponent::TestCase
  test "the URL and the configuration each have a Copy button, with a placeholder token" do
    render_inline Admin::TokensScreen::ConnectStepComponent.new(mcp_url: "https://example.test/mcp", config: "{ \"token\": \"YOUR_TOKEN\" }")

    assert_selector "h2", text: "2 · Add it to your assistant"
    assert_selector "code#mcp-url", text: "https://example.test/mcp"
    assert_selector "pre#mcp-client-config", text: "YOUR_TOKEN"
    assert_selector "pre#mcp-client-config[data-admin--tokens--reveal-target]", count: 0
    assert_selector "button[data-admin--tokens--reveal-source-param=mcp-url]", text: "Copy"
    assert_selector "button[data-admin--tokens--reveal-source-param=mcp-client-config]", text: "Copy"
  end

  test "on the reveal the configuration holds the token and is blanked on pagehide" do
    render_inline Admin::TokensScreen::ConnectStepComponent.new(mcp_url: "u", config: "Bearer #{"b" * 64}", raw_token: "b" * 64)

    assert_selector "pre#api-token-config[data-admin--tokens--reveal-target=secret]", text: "b" * 64
    assert_selector "button[data-admin--tokens--reveal-source-param=api-token-config]", text: "Copy"
  end
end
