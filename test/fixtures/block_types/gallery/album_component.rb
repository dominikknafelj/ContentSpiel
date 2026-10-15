# An outside block type's component, as an engine would ship it, for the
# hook's tests (block types spec, decision 11). Not autoloaded: required by
# test/support/gallery_album.rb.
module Gallery
  class AlbumComponent < ApplicationComponent
    def initialize(block:, page:)
      @block = block
      @page = page
    end

    def render? = title.present?

    private

    attr_reader :block, :page

    def title = block.settings_object(fallback: true)&.title
  end
end
