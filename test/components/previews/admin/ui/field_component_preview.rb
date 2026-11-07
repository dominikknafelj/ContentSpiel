module Admin
  module Ui
    # `Admin::Ui::FieldComponent`: one example per state the wrapper chrome
    # draws (a plain field, errors, a translated field's read-only original,
    # an original that changed since, the untranslated hint), plus one example
    # that renders every field type from a test-only definition built entirely
    # in memory -- proof the dispatcher covers every type
    # `ContentModel::Definition::Field` supports, in the same spirit as
    # `test/support/test_types.rb`.
    class FieldComponentPreview < ViewComponent::Preview
      Field = ContentModel::Definition::Field

      def rest
        render Admin::Ui::FieldComponent.new(field: Field.new(name: "subtitle", type: :string, options: {}), form_name: "page", value: "A shorter, secondary line", locale: "en")
      end

      def invalid
        field = Field.new(name: "venue", type: :string, options: { required: true })
        render Admin::Ui::FieldComponent.new(field:, form_name: "post[fields]", value: nil, locale: "en", errors: [ "can't be blank" ])
      end

      def translated
        field = Field.new(name: "headline", type: :string, options: { translated: true })
        render Admin::Ui::FieldComponent.new(field:, form_name: "post[fields]", value: nil, original: "Willkommen", locale: "de")
      end

      def outdated
        field = Field.new(name: "headline", type: :string, options: { translated: true })
        render Admin::Ui::FieldComponent.new(field:, form_name: "post[fields]", value: "Hallo", original: "Hello!", locale: "de", translation_state: :outdated,
          translation_confirm: { record_type: "Post", record_id: 4, field: "headline", locale: "de" })
      end

      def untranslated_hint
        field = Field.new(name: "cite", type: :url, options: {})
        render Admin::Ui::FieldComponent.new(field:, form_name: "block[settings]", value: "https://example.com", locale: "de")
      end

      # A definition covering every scalar and group type at once. `group`/
      # `groups` need a real `FieldGroups` entry to resolve their `of:`, so
      # this hands a sidecar template (`every_field_type.html.erb`) the field
      # list and lets *it* register a test-only group (`test/…`, the prefix
      # kept for tests), render every field, then restore the registries --
      # `render`/`render_with_template` only ever return a description of
      # what to render (the actual rendering happens later, inside
      # `ComponentPreviewsController`), so registering here and cleaning up in
      # this method's own `ensure` would unregister the group before that
      # later render ever ran it.
      def every_field_type
        fields = [
          Field.new(name: "title", type: :string, options: { required: true }),
          Field.new(name: "body", type: :text, options: {}),
          Field.new(name: "limit", type: :integer, options: { min: 1, max: 10 }),
          Field.new(name: "featured", type: :boolean, options: {}),
          Field.new(name: "starts_on", type: :date, options: {}),
          Field.new(name: "link", type: :url, options: {}),
          Field.new(name: "role", type: :select, options: { options: { "ic" => "Individual contributor", "lead" => "Lead" } }),
          Field.new(name: "kind", type: :content_type, options: {}),
          Field.new(name: "topic", type: :tag, options: {}),
          Field.new(name: "detail", type: :group, options: { of: "test/preview_detail" }),
          Field.new(name: "details", type: :groups, options: { of: "test/preview_detail" })
        ]

        render_with_template(locals: { fields: fields })
      end
    end
  end
end
