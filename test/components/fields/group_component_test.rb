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

  test "a row is named by the field's own label where its type gives one" do
    definition = ContentModel::FieldGroupDefinition.new("cta").tap { |t| t.field :url, :url, label: "Address" }

    render_inline(Fields::GroupComponent.new(value: ContentModel::FieldSet.for(definition).new({ "url" => "https://example.com" })))

    assert_selector "dt", exact_text: "Address"
  end
end
