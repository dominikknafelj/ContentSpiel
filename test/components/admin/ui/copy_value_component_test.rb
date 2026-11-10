require "test_helper"

# A value a person copies exactly (a token, an address, a command, a
# configuration) in a box beside a Copy button. The value is the box's text
# and nothing else: the one copy script reads it from there, so no attribute
# holds a second copy of it, which matters most for a token shown once.
class Admin::Ui::CopyValueComponentTest < ViewComponent::TestCase
  REVEAL = Rails.root.join("app/javascript/controllers/admin/tokens/reveal_controller.js")

  # Every attribute value of the rendered fragment.
  def attribute_values
    Nokogiri::HTML::DocumentFragment.parse(rendered_content).css("*").flat_map { |node| node.attribute_nodes.map(&:value) }
  end

  test "the value is escaped text in its source target, the button is named for it, and no text value is written" do
    command = %(echo "<b>&" 'x')
    render_inline(Admin::Ui::CopyValueComponent.new(id: "check-command-0", value: command, copy_label: "Copy command for Site address"))

    root = page.find("div[data-controller='admin--ui--clipboard']")
    assert_includes JSON.parse(root["data-messages"]).keys, "components.ui.copy_value.copied"
    assert_selector "code#check-command-0[data-admin--ui--clipboard-target=source]", exact_text: command
    assert_no_selector "code b"
    assert_includes page.find("code#check-command-0")[:class].split, "font-cs-mono"
    assert_selector "button[type=button][aria-label='Copy command for Site address'][data-admin--ui--clipboard-target=button]" \
                    "[data-action='click->admin--ui--clipboard#copy']", exact_text: "Copy"
    assert_selector "span.sr-only[role=status][aria-live=polite][data-admin--ui--clipboard-target=status]", visible: :all
    assert_empty attribute_values.grep(/<b>|echo/), "the value is written into no attribute"
    assert_no_selector "[data-admin--ui--clipboard-text-value], [data-admin--ui--clipboard-url-value]"

    render_inline(Admin::Ui::CopyValueComponent.new(id: "config", value: "{\n  \"a\": 1\n}", copy_label: "Copy the client configuration", layout: :block))
    assert_selector "pre#config[data-admin--ui--clipboard-target=source]", text: "\"a\": 1"
    assert_no_selector "code"
  end

  test "without copyable it is the same value box alone: no script, no button, no status" do
    copy_box = Nokogiri::HTML::DocumentFragment.parse(render_inline(Admin::Ui::CopyValueComponent.new(id: "check-command-0", value: "bin/rails x", copy_label: "Copy command for Mail")).to_html)
    plain = Nokogiri::HTML::DocumentFragment.parse(render_inline(Admin::Ui::CopyValueComponent.new(id: "check-command-0", value: "bin/rails x", copy_label: "Copy command for Mail", copyable: false)).to_html)
    assert_equal copy_box.at_css("code")[:class], plain.at_css("code")[:class], "one look for the value, with or without Copy"
    assert_selector "div > code#check-command-0", exact_text: "bin/rails x"
    assert_no_selector "[data-controller], [data-messages], [data-admin--ui--clipboard-target], [role=status]", visible: :all
    assert_no_selector "button"
  end

  test "an unknown layout is refused" do
    assert_raises(ArgumentError) { Admin::Ui::CopyValueComponent.new(id: "x", value: "v", copy_label: "Copy", layout: :wide) }
  end

  test "the revealed token is in no attribute, Copy writes it from the text, and pagehide blanks it" do
    token = "f0" * 32
    render_inline(Admin::Ui::CopyValueComponent.new(id: "api-token-value", value: token, copy_label: "Copy token", layout: :block,
      source_data: { "admin--tokens--reveal-target": "secret" }))

    assert_selector "pre#api-token-value[data-admin--ui--clipboard-target=source][data-admin--tokens--reveal-target=secret]", exact_text: token
    assert_equal 1, rendered_content.scan(token).size, "the token is written once, as the source's text"
    assert attribute_values.none? { |value| value.include?(token) }, "an attribute holds the token"

    # Copy writes the source's text: the box hands the script no text or url
    # value to prefer (the browser test "Copy writes the command, says
    # Copied, …" holds that what is copied is that text).
    assert_no_selector "[data-admin--ui--clipboard-text-value], [data-admin--ui--clipboard-url-value]"
    # The token's text is a `secret` target, the one the reveal blanks at
    # pagehide. Source text is the only seam for the blanking itself: no
    # browser test observes the blanking, and a component test runs no script.
    assert_includes REVEAL.read, %(window.addEventListener("pagehide", this.forget))
    assert_includes REVEAL.read, %(this.secretTargets.forEach((element) => { element.textContent = "" }))
  end

  test "a caller's class is added to the box's own" do
    render_inline(Admin::Ui::CopyValueComponent.new(id: "mcp-url", value: "https://example.test/mcp", copy_label: "Copy the MCP URL", class: "mt-1"))

    classes = page.find("div[data-controller='admin--ui--clipboard']")[:class].split
    assert_includes classes, "mt-1"
    assert_includes classes, "flex"
  end
end
