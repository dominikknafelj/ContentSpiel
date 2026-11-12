require "test_helper"

# The recovery codes, shown once. The codes are the copy box's text and stand
# in no attribute: Download builds its file in the browser from that text.
class Admin::Ui::RecoveryCodesComponentTest < ViewComponent::TestCase
  CODES = %w[k3f9-x2mq 7hd2-p8vz m4qa-9tzc w6ne-h3ry b8ux-d5kj r2cv-n7ps t9gy-a4wm e5zh-j6bq c7lp-u3xd f2sk-v8nt].freeze

  def attribute_values
    Nokogiri::HTML::DocumentFragment.parse(rendered_content).css("*").flat_map { |node| node.attribute_nodes.map(&:value) }
  end

  test "ten codes, the words, Done disabled, and no code in any attribute" do
    render_inline(Admin::Ui::RecoveryCodesComponent.new(codes: CODES))

    assert_selector "dialog[data-admin--ui--dialog-open-on-load] h2", text: "Save your recovery codes", visible: :all
    assert_text "Each code signs you in once when your passkeys aren't at hand.", normalize_ws: true
    pre = page.find("pre#recovery-codes-copy", visible: :all)
    assert_equal CODES.join("\n"), pre.text(:all)
    assert_includes pre[:class].split, "font-cs-mono"
    assert_selector "[aria-label='Recovery codes'] pre, pre[aria-label='Recovery codes'], [aria-label='Recovery codes']", visible: :all
    assert_selector "button[aria-label='Copy codes']", visible: :all
    assert_selector "button", text: "Download", visible: :all
    assert_selector "input[type=checkbox]#recovery-codes-saved", visible: :all
    assert_selector "label", text: "I have saved these codes", visible: :all
    assert_selector "form[method=dialog] button[type=submit][disabled]", text: "Done", visible: :all
    CODES.each { |code| assert_empty attribute_values.grep(/#{Regexp.escape(code)}/), "#{code} stands in an attribute" }
  end

  test "page frame draws a heading and a Done link to done_href" do
    render_inline(Admin::Ui::RecoveryCodesComponent.new(codes: CODES, frame: :page, done_href: "/cs-studio/account"))

    assert_selector "h1.text-h1", text: "Save your recovery codes"
    assert_no_selector "dialog", visible: :all
    assert_selector "a[href='/cs-studio/account'][aria-disabled=true]", text: "Done"
    CODES.each { |code| assert_empty attribute_values.grep(/#{Regexp.escape(code)}/) }
  end

  test "an unknown frame, or a page with nowhere to go, is refused" do
    assert_raises(ArgumentError) { Admin::Ui::RecoveryCodesComponent.new(codes: CODES, frame: :sheet) }
    assert_raises(ArgumentError) { Admin::Ui::RecoveryCodesComponent.new(codes: CODES, frame: :page) }
  end
end
