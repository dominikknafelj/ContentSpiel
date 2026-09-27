require "test_helper"

class Fields::GroupComponentTest < ActiveSupport::TestCase
  include ComponentTestHelper

  test "renders one label/value row per scalar field" do
    definition = ContentModel::FieldGroupDefinition.new("cta").tap do |t|
      t.field :label, :string
      t.field :url, :url
    end
    value = ContentModel::FieldSet.for(definition).new({ "label" => "Get in touch", "url" => "https://example.com" })

    render_inline(Fields::GroupComponent.new(value: value))

    assert_selector "dt", text: "Label"
    assert_selector "dd", text: "Get in touch"
    assert_selector "dt", text: "Url"
    assert_selector "dd", text: "https://example.com"
  end
end
