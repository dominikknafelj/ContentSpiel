module Admin
  module Ui
    # A native checkbox in the design system's skin: `.cs-checkbox` (content-spiel.tailwind.css) gives it the accent fill,
    # a 2px radius and a visible focus ring, from tokens -- so the users form's
    # group cards, the group form's members and the permission matrix all tick
    # the same way, in both themes.
    #
    # It is still a plain `<input type=checkbox>`: the form posts exactly what
    # a `check_box_tag` did, and the unchecked value (a hidden field sent
    # first, so an empty list still arrives) stays the caller's business.
    # `label:` renders the `<label for>` beside it when a caller has no
    # richer label of its own (the matrix and the member rows wrap their own);
    # anything else (`data:`, `aria:`, `form:`) passes through to the input.
    class CheckboxComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "A native checkbox named by its label (the label: given here, or the caller's own around it), toggled with Space.",
        motion: :none,
        content_edges: %i[short long],
        widths: :fluid,
        interface: %i[name value checked id label disabled],
        limits: [
          "It posts what a check_box_tag posts: the unchecked value's hidden field is the caller's.",
          "A richer label than one line of text is the caller's to draw around it."
        ],
        states: %i[unchecked checked disabled focus],
        keys: [],
        slots: [],
        controller: nil
      )

      def initialize(name:, value: "1", checked: false, id: nil, label: nil, disabled: false, **html)
        @name = name
        @value = value
        @checked = checked
        @id = id
        @label = label
        @disabled = disabled
        @html = html
      end

      private

      attr_reader :name, :value, :checked, :id, :label, :disabled, :html

      def input_attrs
        html.merge(type: "checkbox", name: name, value: value, id: id, checked: checked || nil, disabled: disabled || nil,
          class: [ "cs-checkbox", html[:class] ].compact.join(" "))
      end
    end
  end
end
