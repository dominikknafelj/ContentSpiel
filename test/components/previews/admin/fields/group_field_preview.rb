module Admin
  module Fields
    # `Admin::Fields::GroupField` needs a real `FieldGroups` entry to
    # resolve `of:` -- see `Admin::FieldComponentPreview#every_field_type`
    # for why the register/cleanup has to live in the sidecar template
    # (`default.html.erb`), not this method.
    class GroupFieldPreview < ViewComponent::Preview
      def default
        field = ContentModel::Definition::Field.new(name: "speaker", type: :group, options: { of: "test/preview_speaker" })
        render_with_template(locals: { field: field })
      end
    end
  end
end
