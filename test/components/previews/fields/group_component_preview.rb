module Fields
  # `Fields::GroupComponent` (open-types spec §5): the generic renderer for
  # any field group. Built entirely in memory -- a bare
  # `ContentModel::FieldGroupDefinition` and its `FieldSet`, not registered
  # into `FieldGroups` at all -- since nothing here needs a real record or a
  # database row, unlike the components that render a `block`/`post`.
  class GroupComponentPreview < ViewComponent::Preview
    def default
      definition = ContentModel::FieldGroupDefinition.new("cta").tap do |t|
        t.label "Call to action"
        t.field :label, :string
        t.field :url, :url
      end
      value = ContentModel::FieldSet.for(definition).new({ "label" => "Get in touch", "url" => "https://example.com" })

      render Fields::GroupComponent.new(value: value)
    end
  end
end
