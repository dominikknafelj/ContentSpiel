module Admin
  module Ui
    # `Admin::Ui::FieldComponent` (cs-studio spec §4.3/§6.2): one example per
    # dispatch outcome the wrapper chrome cares about (a plain field, errors,
    # a translated field's read-only original, the untranslated hint), plus
    # one example that renders every field type from a test-only definition
    # built entirely in memory -- proof the dispatcher covers every type
    # `ContentModel::Definition::Field` supports, the same "open-type proof"
    # spirit as `test/support/test_types.rb`.
    class FieldComponentPreview < ViewComponent::Preview
      Field = ContentModel::Definition::Field

      def plain
        render Admin::Ui::FieldComponent.new(field: Field.new(name: "subtitle", type: :string, options: {}), form_name: "page", value: "A shorter, secondary line", locale: "en")
      end

      def required_with_errors
        field = Field.new(name: "venue", type: :string, options: { required: true })
        render Admin::Ui::FieldComponent.new(field:, form_name: "post[fields]", value: nil, locale: "en", errors: [ "can't be blank" ])
      end

      def translated_with_original
        field = Field.new(name: "headline", type: :string, options: { translated: true })
        render Admin::Ui::FieldComponent.new(field:, form_name: "post[fields]", value: nil, original: "Willkommen", locale: "de")
      end

      def untranslated_hint
        field = Field.new(name: "cite", type: :url, options: {})
        render Admin::Ui::FieldComponent.new(field:, form_name: "block[settings]", value: "https://example.com", locale: "de")
      end

      # A definition covering every scalar and group type at once. `group`/
      # `groups` need a real `FieldGroups` entry to resolve their `of:`, so
      # this hands a sidecar template (`every_field_type.html.erb`) the field
      # list and lets *it* register a test-only group (`test/…`, spec §3.2a's
      # reserved prefix), render every field, then restore the registries --
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
