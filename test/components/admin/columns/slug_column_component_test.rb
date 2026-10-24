require "test_helper"

class Admin::Columns::SlugColumnComponentTest < ViewComponent::TestCase
  test "the address is shown once: the prefix and the slug in the field, and no line under it" do
    render_inline Admin::Columns::SlugColumnComponent.new(value: "about-us", base_url: "https://example.com/company")

    assert_selector "input[type=text][name=slug][value='about-us']"
    assert_selector ".admin-prefix-input span", text: "example.com/company/"
    assert_no_text "example.com/company/about-us"
    assert_no_selector "[data-admin--editor--slug-preview-target=output], [data-slug-preview-base]"
  end

  test "renders errors under the input" do
    render_inline Admin::Columns::SlugColumnComponent.new(value: "", base_url: "https://example.com", errors: [ "can't be blank" ])

    assert_text "can't be blank"
  end

  test "the URL prefix never doubles the slash, whatever the base looks like" do
    {
      "https://example.com" => "example.com/",
      "https://example.com/" => "example.com/",
      "https://example.com/de" => "example.com/de/",
      "https://example.com/de/" => "example.com/de/",
      "https://example.com/de//" => "example.com/de/",
      "" => "/"
    }.each do |base, prefix|
      component = Admin::Columns::SlugColumnComponent.new(value: "about", base_url: base)
      assert_equal prefix, component.prefix, base.inspect
      render_inline(component)
      assert_no_text "//about"
    end
  end

  test "the slug sits in a prefix input and keeps its data attributes and error slot" do
    render_inline Admin::Columns::SlugColumnComponent.new(value: "x", base_url: "/de", id: "page_slug", html_name: "page[slug]",
      errors: [ "is taken" ], data: { "admin--editor--slug-preview-target": "slug" })

    assert_selector ".admin-prefix-input span.bg-sunken", text: "/de/"
    assert_selector "input#page_slug[name='page[slug]'][data-admin--editor--slug-preview-target=slug][aria-invalid=true]"
    assert_selector "#page_slug-errors", text: "is taken"
  end
end
