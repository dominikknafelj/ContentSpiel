require "test_helper"

class Admin::Columns::RichTextColumnComponentTest < ViewComponent::TestCase
  test "renders a Trix editor named after the column" do
    render_inline Admin::Columns::RichTextColumnComponent.new(name: "body", value: "<p>Hello</p>")

    assert_selector "trix-editor"
    assert_selector "input[type=hidden][name=body]", visible: false
  end

  test "renders the default-locale original as sanitized html, labelled" do
    render_inline Admin::Columns::RichTextColumnComponent.new(name: "body", value: nil, original: "<p onclick=\"x()\">Hallo</p>")

    assert_text "Hallo"
    assert_text Locales.name(Locales.default, native: true)
    refute_match(/onclick/, rendered_content)
  end

  test "no original column when none is given" do
    render_inline Admin::Columns::RichTextColumnComponent.new(name: "body", value: "<p>Hello</p>")

    refute_selector "[data-original-for]"
  end

  # Fix round 1 (Task 7 review): regression test for the `name` -> `html_name`
  # fix -- a caller nesting this under a form object (`Admin::
  # BlockCardComponent`, `Admin::PostFormComponent`) needs the Trix hidden
  # field's own `name=` to carry that nesting (`block[body]`/`post[body]`),
  # not the bare column name `name:` only drives the label/`data-field-name`
  # for.
  test "an explicit html_name, not the bare name, drives the hidden field's own name" do
    render_inline Admin::Columns::RichTextColumnComponent.new(name: "body", html_name: "post[body]", value: "<p>Hello</p>")

    assert_selector "input[type=hidden][name='post[body]']", visible: false
    refute_selector "input[type=hidden][name=body]", visible: false
  end
end
