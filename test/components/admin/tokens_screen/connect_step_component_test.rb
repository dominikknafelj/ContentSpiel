require "test_helper"

class Admin::TokensScreen::ConnectStepComponentTest < ViewComponent::TestCase
  test "the URL and the configuration are copy boxes, with a placeholder token" do
    render_inline Admin::TokensScreen::ConnectStepComponent.new(mcp_url: "https://example.test/mcp", config: "{ \"token\": \"YOUR_TOKEN\" }")

    assert_selector "h2", text: "2 · Add it to your assistant"
    assert_selector "[data-controller='admin--ui--clipboard'] code#mcp-url[data-admin--ui--clipboard-target=source]", exact_text: "https://example.test/mcp"
    assert_selector "[data-controller='admin--ui--clipboard'] pre#mcp-client-config[data-admin--ui--clipboard-target=source]", text: "YOUR_TOKEN"
    assert_selector "pre#mcp-client-config[data-admin--tokens--reveal-target]", count: 0
    assert_selector "button[aria-label='Copy the MCP URL']", exact_text: "Copy"
    assert_selector "button[aria-label='Copy the client configuration']", exact_text: "Copy"
    assert_no_selector "[data-admin--tokens--reveal-target=status]", visible: :all
  end

  test "on the reveal the configuration holds the token and is blanked on pagehide" do
    token = "b" * 64
    render_inline Admin::TokensScreen::ConnectStepComponent.new(mcp_url: "u", config: "Bearer #{token}", raw_token: token)

    assert_selector "pre#api-token-config[data-admin--ui--clipboard-target=source][data-admin--tokens--reveal-target=secret]", text: token
    assert_selector "button[aria-label='Copy the client configuration']", exact_text: "Copy"
    assert_equal 1, rendered_content.scan(token).size, "the token is written once, as the configuration's text"
  end
end
