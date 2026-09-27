module Admin
  module Columns
    # Shared shape for the "opted-in column" field components (spec §4.3):
    # unlike `Admin::Fields::*`, which render a schema field named under a
    # `form_name` prefix supplied by `FieldComponent`, a column field edits
    # an existing AR column directly (`page.title`, `post.body`, a block's
    # `caption`) and is named by that bare column name -- there's no prefix
    # to compute, since the record's own `update`/save endpoint reads
    # `params[name]` straight off the top level. `original`/`errors` follow
    # the same convention `FieldComponent` gives every schema field, so a
    # page/post editor can lay out its typed fields and its column fields
    # side by side with identical read-only-original and error-slot
    # behaviour.
    class Base < Admin::AdminComponent
      def initialize(name:, value:, original: nil, errors: [], locale: nil)
        @name = name
        @value = value
        @original = original
        @errors = errors
        @locale = locale
      end

      def show_original? = original.present?

      def default_locale_name = Locales.name(Locales.default, native: true)

      def errors_id = "#{name}-errors"

      private

      attr_reader :name, :value, :original, :errors, :locale
    end
  end
end
