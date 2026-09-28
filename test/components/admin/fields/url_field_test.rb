require "test_helper"

class Admin::Fields::UrlFieldTest < ViewComponent::TestCase
  Field = ContentModel::Definition::Field

  test "renders a url input named and valued" do
    field = Field.new(name: "cite", type: :url, options: {})
    render_inline Admin::Fields::UrlField.new(field:, form_name: "block[settings]", value: "https://example.com", locale: "en")

    assert_selector "input[type=url][name='block[settings][cite]'][value='https://example.com']"
  end
end
