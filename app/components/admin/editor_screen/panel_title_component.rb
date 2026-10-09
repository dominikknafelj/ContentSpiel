module Admin
  module EditorScreen
    # "Image · column 2": the heading of a block's form where it is drawn as
    # a section's panel (sections spec §4.3). The open form is below the
    # lanes, not in its column, so its heading says which column it belongs
    # to.
    #
    # Its own component because the words are redrawn without the form: a
    # block's column changes under an open form -- a narrower layout folds
    # it, another tab's layout change is found out by a refused add -- and
    # the answer then rewrites this text inside the heading and leaves the
    # panel, its form and what is typed in it alone (`Admin
    # ::ContentBlocksController#section_structure_streams`). The panel draws
    # its heading through this component too (`Admin::BlockCardComponent`),
    # so the words a stream brings are the words a page load draws. Text
    # only: the heading element, with the id the panel's region is named by,
    # is the block card's and stays.
    class PanelTitleComponent < AdminComponent
      def initialize(block:)
        @block = block
      end

      # Escaped here: a component's `call` is taken as markup, and the type's
      # label is whatever a plugin registered.
      def call = ERB::Util.html_escape(t(".title", type: block.definition&.label || block.block_type, column: block.section_column))

      private

      attr_reader :block
    end
  end
end
