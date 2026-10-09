module Notes
  # What a block is called where a note names it (the handoff's decision 8):
  # its type, where it stands in a section, and something that tells it from
  # the other blocks of that type -- a block has no name of its own in this
  # CMS. That is the first words of its text in the language being read, an
  # image's file name, or for a block with neither its place on the page
  # ("Block 3"). Data only: `Admin::NotesScreen::SubjectComponent` words it.
  #
  # Built once from ALL of a page's blocks (or of several pages', for the
  # inbox), which whoever asks has loaded already (the list reads them for
  # the order of its groups): the text is
  # read from those rows, the place from their `BlockOutline`, a section's
  # type from its own row. So naming a block costs no statement -- except an
  # image's file name, which is on the image's stored file: `preload_images`
  # reads those for the blocks about to be named, in one pass of three
  # statements whatever their number, and without it an image block is named
  # by its place like an empty one rather than by a query of its own.
  class Heading
    # `type` and `section` are type labels ("Rich text", "Section");
    # `column` is the block's column in its section, nil outside one. Of
    # `words` and `file_name` at most one is set; `position` always is.
    Name = Data.define(:type, :section, :column, :words, :file_name, :position)

    # "The first 4-6 words": six, and `more` says the text went on.
    WORDS = 6

    def initialize(blocks, locale:)
      @blocks = blocks.to_a
      @locale = locale.to_s.presence || Locales.default
      @by_id = @blocks.index_by(&:id)
    end

    # The image blocks among `blocks` that have not been read yet, in one
    # pass. Asked again with the same blocks it reads nothing.
    def preload_images(blocks)
      @named_images ||= Set.new
      images = blocks.select { |block| uses?(block, "image") && block.media_asset_id && !@named_images.include?(block.id) }
      ActiveRecord::Associations::Preloader.new(records: images, associations: { media_asset: { file_attachment: :blob } }).call if images.any?
      @named_images.merge(images.map(&:id))
      self
    end

    def for(block)
      section = @by_id[block.section_id] if block.section_id
      Name.new(type: label(block), section: (label(section) if section), column: (block.section_column if block.section_id),
        words: words(block), file_name: file_name(block), position: places.fetch(block.id, 0))
    end

    private

    def label(block) = block.definition&.label || block.block_type

    def uses?(block, column) = block.definition&.uses_columns&.include?(column) || false

    # 1-based, in the order the page shows its blocks; a section counts.
    # Counted per page: the inbox hands over the blocks of several.
    def places
      @places ||= @blocks.group_by { |block| [ block.owner_type, block.owner_id ] }.values.flat_map do |blocks|
        BlockOutline.new(blocks).reading_order.each_with_index.map { |block, index| [ block.id, index + 1 ] }
      end.to_h
    end

    def file_name(block)
      return unless @named_images&.include?(block.id)

      asset = block.media_asset
      asset.file.filename.to_s.presence if asset&.file&.attached?
    end

    # An image block is named by its file, never by its caption. Otherwise
    # the body's text in the language being read, the default language's
    # when that one is blank, and the caption for a type that has no body.
    def words(block)
      return if uses?(block, "image")

      text = if uses?(block, "body") then [ @locale, Locales.default ].uniq.lazy.filter_map { |code| block.body_document(locale: code).plain_paragraphs.first }.first
      elsif uses?(block, "caption") then Locales.read(block, :caption, locale: @locale)
      end
      first_words(text)
    end

    def first_words(text)
      all = text.to_s.split
      return if all.empty?

      all.size > WORDS ? "#{all.first(WORDS).join(" ")}…" : all.join(" ")
    end
  end
end
