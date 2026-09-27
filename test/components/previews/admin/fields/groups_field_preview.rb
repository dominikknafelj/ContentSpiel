module Admin
  module Fields
    # See `GroupFieldPreview` for why the `FieldGroups` register/cleanup
    # lives in the sidecar template, not here.
    class GroupsFieldPreview < ViewComponent::Preview
      def default
        field = ContentModel::Definition::Field.new(name: "speakers", type: :groups, options: { of: "test/preview_speaker" })
        render_with_template(locals: { field: field })
      end
    end
  end
end
