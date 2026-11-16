module Publishing
  # How a record's rows differ from its newest copy (drafts spec §4.4): the
  # overview the publish dialog shows, as data. A component words it.
  #
  # Both sides are compared in the form a copy is stored in
  # (`Snapshot.of`), so "the same" means "a copy taken now would hold the
  # same". A block is CHANGED when a content column differs, else MOVED when
  # its container differs or, among the blocks both sides have, it is not
  # where the longest run of blocks in unchanged order leaves it. A block's
  # timestamps, its translation bookkeeping and its bare `position` are not
  # compared; neither are a record's (`Publishable::BOOKKEEPING`), which are
  # in a copy as a record of the marks when it was taken (a discard does not
  # put them back), and say nothing a person edited.
  #
  # THE MARK IS NOT THE ANSWER. `unpublished_changes_at` says THAT something
  # was written, cheaply, for every list; this says WHAT, and is asked for
  # one record, when the dialog opens or a publish is pressed. It may find
  # nothing where the mark is set (typed and typed back).
  #
  # A record with no copy has nothing to compare with: none, no version.
  class Changes
    Block = Data.define(:kind, :block)

    BLOCK_CONTENT = %w[block_type settings translated_settings body caption alt media_asset_id listed_tag_id].freeze
    BLOCK_TRANSLATED = %w[translated_settings body caption alt].freeze
    TRANSLATED = { "Page" => %w[title subtitle meta_title meta_description hero_alt], "Post" => %w[title excerpt body translated_metadata] }.freeze

    # `version` is the was side of an overview (`of`, `new`); `between` names
    # both. Each side is a `Publishing::Version` or `:working`, the rows as
    # `Snapshot.of` reads them. No version at all compares the rows with
    # themselves.
    attr_reader :record, :version, :fields, :blocks, :locales, :sides

    def self.of(record) = new(record, Publishing.baseline(record))

    # What `to` changed from `from`, whichever is the later: the names are the
    # same either way round, and a block only one side has is added or removed
    # as the direction says. Stand-ins (`stand_ins`) pair a block that came
    # back under a new id, so two old copies compare as a copy and the rows do.
    def self.between(record, from:, to:) = new(record, from, to: to)

    def initialize(record, version, to: :working)
      @record = record
      @version = version
      @changed_locales = Set.new
      @was_source = version || :working
      @now_source = to
      now = side(to)
      was = version ? side(version) : now
      @sides = [ was, now ]
      @block_sides = {}.compare_by_identity
      @block_places = {}.compare_by_identity
      @fields = changed_fields(was, now)
      @blocks = changed_blocks(was.fetch("blocks", []), now.fetch("blocks", []))
      @locales = @changed_locales.to_a.sort
    end

    # The stored form of one block of this comparison on each side, `[was,
    # now]`, a side nil where the block is not on it: the text of a changed
    # block is read from these (`Publishing::TextDiff`), never from the row,
    # which is the working version's whatever the sides are.
    def sides_of(change) = @block_sides.fetch(change.block)

    # Where one block of this comparison stands on each side, `[was, now]`:
    # its place in the side's reading order, counted from 1 among all its
    # blocks (a section's inner blocks included), nil where it is not on a
    # side. What a move is worded with ("now 4th, was 2nd").
    def places_of(change) = @block_places.fetch(change.block)

    def none? = fields.empty? && blocks.empty?

    # What publishing the rows of `record` at `now` would do to the ADDRESSES
    # of live records, the record's own among them, as data
    # (`PublicSite::Paths.foresee`, a `Foreseen`): `lost`, those left
    # without one (`{ record_type:, record_id:, locale:, path: }`), and
    # `moved`, those that would stand at another (the same with `to:` and
    # `redirects:`, whether the old address then sends a visitor on).
    # Information, never a refusal: the publish dialog words both (Task 7,
    # and the hand test that found a moving post unnamed). Nothing of either
    # when nothing differs (publishing nothing takes and moves nothing) and
    # for a record with no time.
    #
    # NEVER FROM A GET, and not part of `Changes.of`, which is cheap and
    # lock-free. This TRIES a publish: it takes the record's ROW LOCK (a
    # colleague's block autosave on that page waits at `lock_owner` for the
    # length of the call) and WRITES inside a savepoint it rolls back (a copy,
    # `public_paths` rows, `media_usages`, the mark), reading every current
    # address twice. It can be one side of a `(locale, path)` wait. So the
    # request that asks is a POST, sent through the write queue when the
    # dialog opens (Task 7), serialised with the tab's own saves.
    def self.addresses(record, now: Time.current)
      return PublicSite::Paths::Foreseen.nothing if record.published_at.nil? || of(record).none?

      PublicSite::Paths.foresee(record, now: now)
    end

    # A per-language value without the languages that hold nothing: a blank,
    # and a rich-text document with no content. A body is emptied by writing
    # an empty document (`HasRichTextBody#assign_body` never deletes a
    # language), so a language typed into and emptied again, or one a discard
    # emptied, is the same as a language that was never written: a visitor
    # is shown the same nothing. Also for `Publishing::DiscardChanges`, which
    # must judge "differs" exactly as this does.
    def self.languages_with_text(value)
      return {} unless value.is_a?(Hash)

      value.compact_blank.reject { |_locale, text| text.is_a?(Hash) && text["type"] == "doc" && RichText::Document.new(text).blank? }
    end

    # A BLOCK THAT CAME BACK UNDER A NEW ID is the block it was. "Discard
    # changes" creates a block the rows had lost again, as a new row
    # (`Publishing::DiscardChanges`), and nothing a visitor or an editor can
    # see tells it from the one in the copy: read by id alone it would be one
    # block removed and one added until the next publish, and the next
    # discard would delete it (with its notes) to create it once more. So a
    # block only the rows have STANDS FOR a block only the copy has when the
    # two are the same in every content column and in their place (the same
    # column of the same container, a section itself being judged this way
    # first), each once, in reading order.
    #
    # AN IMAGE THAT WENT IS NO IMAGE. A return writes a block whose library
    # image is gone or in the trash with none (`Publishing::ReturnTo`), so
    # here an image id that is not a kept library image reads as nil on both
    # sides: the block made again without it stands for the copy's block,
    # and the next return keeps it, and its notes, instead of making it once
    # more. `kept_images` is the set of kept ids among both sides' (the
    # return hands in the one it read; read here in one statement when not).
    #
    # `{ the row's id => the copy's id }` for such pairs, from the two sides
    # in the form a copy stores blocks in. For `changed_blocks` and for the
    # return, which must agree on which block is which.
    def self.stand_ins(was, now, kept_images: nil)
      known = now.map { |block| block["id"] }.to_set
      lost = was.reject { |block| known.include?(block["id"]) }
      return {} if lost.empty?

      kept_images ||= kept_images_among(was + now)
      lost = lost.map { |block| without_gone_image(block, kept_images) }
      copied = was.map { |block| block["id"] }.to_set
      stands_for = {}
      # Top-level blocks (the sections among them) before the blocks inside.
      now.reject { |block| copied.include?(block["id"]) }.partition { |block| block["section_id"].nil? }.flatten.each do |block|
        place = [ stands_for.fetch(block["section_id"], block["section_id"]), block["section_column"] ]
        twin = lost.find { |old| old.values_at("section_id", "section_column") == place && same_content?(old, without_gone_image(block, kept_images)) } or next
        lost.delete(twin)
        stands_for[block["id"]] = twin["id"]
      end
      stands_for
    end

    # The kept library images (`Media::Asset.kept`) among the blocks' image
    # ids, in one statement.
    def self.kept_images_among(blocks)
      ids = blocks.filter_map { |block| block["media_asset_id"] }.uniq
      ids.empty? ? Set.new : Media::Asset.kept.where(id: ids).pluck(:id).to_set
    end

    # The stored block with an image that is not kept read as none.
    def self.without_gone_image(block, kept_images)
      id = block["media_asset_id"]
      id.nil? || kept_images.include?(id) ? block : block.merge("media_asset_id" => nil)
    end

    def self.same_content?(one, other)
      BLOCK_CONTENT.all? do |name|
        next one[name] == other[name] unless BLOCK_TRANSLATED.include?(name)

        languages_with_text(one[name]) == languages_with_text(other[name])
      end
    end

    private

    # reads the rows fresh and takes no lock: the overview must not hold a row
    def side(source)
      return Snapshot.of(record) if source == :working

      { "fields" => source.snapshot.fetch("fields", {}), "tags" => source.snapshot.fetch("tags", []), "blocks" => source.blocks }
    end

    # The blocks of one side as `ContentBlock`s, by id.
    def block_rows(source, ids)
      return ContentBlock.where(id: ids).index_by(&:id) if source == :working

      Snapshot.blocks_from(source, record).index_by(&:id)
    end

    def changed_fields(was, now)
      translated = TRANSLATED.fetch(record.class.polymorphic_name)
      names = (Publishing.content_columns(record) - Publishable::BOOKKEEPING).select do |name|
        differs?(was["fields"][name], now["fields"][name], translated: translated.include?(name))
      end
      names << "tags" unless was.fetch("tags", []).sort_by { |tag| tag["id"] } == now.fetch("tags", []).sort_by { |tag| tag["id"] }
      names
    end

    # Whether two stored values differ. For a per-language value, a blank and
    # a missing language are the same, and each language that differs is
    # noted for `locales`.
    def differs?(before, after, translated:)
      return before != after unless translated

      before = self.class.languages_with_text(before)
      after = self.class.languages_with_text(after)
      (before.keys | after.keys).select { |locale| before[locale] != after[locale] }.each { |locale| @changed_locales << locale }.any?
    end

    def changed_blocks(was, now)
      rows = block_rows(@now_source, now.map { |block| block["id"] })
      stands_for = self.class.stand_ins(was, now)
      rows = rows.transform_keys { |id| stands_for.fetch(id, id) }
      now = now.map { |block| block.merge("id" => stands_for.fetch(block["id"], block["id"]), "section_id" => stands_for.fetch(block["section_id"], block["section_id"])) }
      before = was.index_by { |block| block["id"] }
      after = now.index_by { |block| block["id"] }
      # A block that changed container is moved whatever the order says, so
      # it takes no part in finding the ones that stayed in place.
      stayed = ->(id) { before[id] && after[id] && before[id].values_at("section_id", "section_column") == after[id].values_at("section_id", "section_column") }
      settled = unmoved(was.map { |block| block["id"] }.select(&stayed), now.map { |block| block["id"] }.select(&stayed))

      was_places = was.each_with_index.to_h { |block, index| [ block["id"], index + 1 ] }
      entries = now.each_with_index.filter_map do |block, index|
        id = block["id"]
        old = before[id]
        kind =
          if old.nil? then note_languages(block) && :added
          elsif content_differs?(old, block) then :changed
          elsif old.values_at("section_id", "section_column") != block.values_at("section_id", "section_column") || !settled.include?(id) then :moved
          end
        next unless kind

        Block.new(kind:, block: rows.fetch(id)).tap do |entry|
          @block_sides[entry.block] = [ old, block ]
          @block_places[entry.block] = [ was_places[id], index + 1 ]
        end
      end
      gone = was.reject { |block| after.key?(block["id"]) }
      removed = gone.any? ? block_rows(@was_source, gone.map { |block| block["id"] }) : {}
      entries + gone.map { |block| note_languages(block) && Block.new(kind: :removed, block: removed.fetch(block["id"])).tap { |entry| record_removed(entry, block, was_places) } }
    end

    def record_removed(entry, block, was_places)
      @block_sides[entry.block] = [ block, nil ]
      @block_places[entry.block] = [ was_places[block["id"]], nil ]
    end

    def content_differs?(old, block)
      BLOCK_CONTENT.map { |name| differs?(old[name], block[name], translated: BLOCK_TRANSLATED.include?(name)) }.any?
    end

    # The languages an added or removed block has text in. Always true, so it
    # can stand in a condition.
    def note_languages(block)
      BLOCK_TRANSLATED.each { |name| differs?({}, block[name], translated: true) }
      true
    end

    # The ids that need not move to turn `before` into `after`: a longest
    # common subsequence of the two orders (both hold the same ids).
    def unmoved(before, after)
      at = after.each_with_index.to_h
      runs = []
      before.each do |id|
        best = runs.select { |run| at[run.last] < at[id] }.max_by(&:size)
        runs << [ *best, id ]
      end
      (runs.max_by(&:size) || []).to_set
    end
  end
end
