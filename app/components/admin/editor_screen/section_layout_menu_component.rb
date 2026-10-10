module Admin
  module EditorScreen
    # The layout control in a section's header (sections spec §4.1): a menu
    # of the six layouts, each drawn as a small diagram of its columns.
    #
    # A WIDGET OVER A HIDDEN INPUT, NOT A FIELD. The section's layout is the
    # hidden `block[settings][layout]` of the section's own autosave form
    # (`SectionCardComponent`); a pick writes the layout's name into it and
    # sends the form (`admin--section#chooseLayout`). So the choice is saved
    # as every field of a block is -- with the section's `base_updated_at`,
    # through the write queue, refused with a 409 when it is stale -- and
    # this component holds no state of its own. The input is deliberately not
    # in here: the menu is replaced by the answer to a save (below), and the
    # input must stay the element the form was registered with.
    #
    # ITS OWN COMPONENT, WITH THE ID ON ITS OWN ELEMENT, because it is what a
    # saved layout changes in the header besides the count: which choice is
    # the current one (`aria-current`) and the diagram on the button. The
    # answer replaces this element and nothing else of the form (`Admin
    # ::ContentBlocksController#layout_menu_stream`), and the card draws it
    # through the same door (`SectionCardComponent.layout_menu`), so the menu
    # a stream brings is the menu a page load draws. `admin--section` finds it
    # as its `layoutMenu` target and puts the focus back on its button when
    # the one that was pressed has been replaced.
    #
    # The diagram is for the eye (`aria-hidden`); each choice is named for a
    # screen reader by the words beside it ("One third, two thirds"), and the
    # button by `aria-label`. The weights are the type's own
    # (`BlockTypes::Section::LAYOUTS`), the ones the public grid is built
    # from, so a diagram cannot show proportions the page does not have.
    #
    # `editable:` is not asked here: a viewer who can't edit gets this menu
    # inside the card's disabled fieldset, which disables its button.
    class SectionLayoutMenuComponent < AdminComponent
      def self.dom_id(section) = "section-#{section.id}-layout-menu"

      def initialize(section:)
        @section = section
      end

      def dom_id = self.class.dom_id(section)

      # Name => weights, in the order the type declares them.
      def layouts = BlockTypes::Section::LAYOUTS

      # The layout as the section's columns are counted from it: one never
      # stored reads as the schema's default, and a stored name this code no
      # longer knows as the layout its columns are drawn in, here and on the
      # public page (`BlockTypes::Section.weights`). It is also what the
      # card puts into the form's hidden input, so the form sends the layout
      # the screen shows.
      def current = layouts.key?(stored) ? stored : layouts.key(BlockTypes::Section.weights(stored))

      def current?(name) = name == current

      def diagram(name)
        tag.span(class: "admin-layout-diagram", aria: { hidden: true }) do
          safe_join(layouts.fetch(name).map { |weight| tag.span(style: "flex: #{weight.to_i}") })
        end
      end

      # The button: the current layout's diagram and the word.
      def button_label = safe_join([ diagram(current), tag.span(t(".label")) ])

      def item_class = "admin-layout-choice #{Admin::EditorScreen::BlockCardComponent::MENU_ITEM_CLASS}"

      private

      attr_reader :section

      def stored = section.settings_object(locale: ::Locales.default)&.layout.to_s
    end
  end
end
