require "test_helper"

class Admin::Columns::SlugColumnComponentTest < ViewComponent::TestCase
  test "renders the slug input and a live URL preview line" do
    render_inline Admin::Columns::SlugColumnComponent.new(value: "about-us", base_url: "https://example.com/company")

    assert_selector "input[type=text][name=slug][value='about-us']"
    assert_text "https://example.com/company/about-us"
  end

  test "renders errors under the input" do
    render_inline Admin::Columns::SlugColumnComponent.new(value: "", base_url: "https://example.com", errors: [ "can't be blank" ])

    assert_text "can't be blank"
  end
end
