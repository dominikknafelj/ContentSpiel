module SiteSearch
  # A block type's `search_text` that raised while a copy became words
  # (`SiteSearch::Documents`): reported with the type's name and the error's
  # class name, never the error itself, which may quote the block's content.
  class BlockTextFailed < StandardError
    attr_reader :block_type, :error_class

    def initialize(block_type:, error_class:)
      @block_type = block_type
      @error_class = error_class
      super("#{block_type}: #{error_class}")
    end
  end
end
