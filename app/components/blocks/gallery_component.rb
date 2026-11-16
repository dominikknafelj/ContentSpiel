module Blocks
  # The gallery block on the public site. A theme may replace
  # its template and call only what the type's `theme_methods` names.
  class GalleryComponent < ApplicationComponent
    include Blocks::Contract

    # What the component promises a visitor (`Blocks::Contract`). The
    # interface is the names `t.theme_methods` gives a template, and
    # `words:` the `public.*` keys this component and its template read
    # (none yet): test/values/theme/component_contract_test.rb holds both
    # to the code once the type's line is in the ledger. Say what the
    # sentences say truly, and change them with the template.
    contract(
      accessibility: "One div holding the block's text; it has no role and takes no focus.",
      motion: :none,
      content_edges: %i[short long missing],
      widths: :from_container,
      interface: %i[block page],
      words: [],
      limits: [
        "It draws one translated text and nothing else.",
        "An empty block renders nothing."
      ]
    )

    def initialize(block:, page:)
      @block = block
      @page = page
    end

    # It draws nothing: the template that draws a gallery's images is not
    # written, and the type has no text field to fall back on.
    def render? = false

    private

    attr_reader :block, :page
  end
end
