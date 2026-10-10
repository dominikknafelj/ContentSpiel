module Admin
  module Ui
    # A text input joined to a sunken, read-only prefix cell inside one border
    # (design pass spec §4, handoff A-series "prefix input"): the slug field's
    # "example.com/de/" in front of "about". The wrapper owns the border, so the
    # focus ring (`focus-within`) and the invalid state (danger border) apply to
    # both halves at once; the prefix cell keeps its sunken ground when invalid.
    #
    # `errors` are bare messages; the component only marks the input
    # (`aria-invalid`, `aria-describedby="<id>-errors"`) and colours the wrapper
    # -- the error text itself is rendered by the caller into the element with
    # that id (the per-field error slot autosave streams into), so there is
    # exactly one such element on the page.
    class PrefixInputComponent < AdminComponent
      def initialize(name:, id:, value:, prefix:, errors: [], **html)
        @name = name
        @id = id
        @value = value
        @prefix = prefix
        @errors = Array(errors)
        @html = html
      end

      private

      attr_reader :name, :id, :value, :prefix, :errors, :html

      def errors_id = "#{id}-errors"

      def wrapper_class
        border = errors.any? ? "border-danger" : "border-line-strong focus-within:border-accent"
        "admin-prefix-input flex rounded-cs border #{border} bg-surface"
      end

      def input_attrs
        {
          type: "text", name: name, id: id, value: value,
          class: "min-w-0 flex-1 bg-transparent px-2.5 py-2 text-ink outline-none",
          aria: { invalid: (errors.any? ? "true" : nil), describedby: (errors_id if errors.any?) }.compact
        }.merge(html)
      end
    end
  end
end
