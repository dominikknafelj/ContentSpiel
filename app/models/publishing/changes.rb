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

    attr_reader :record, :version, :fields, :blocks, :locales

    def self.of(record) = new(record, Publishing.baseline(record))

    def initialize(record, version)
      @record = record
      @version = version
      @changed_locales = Set.new
      now = Snapshot.of(record) # reads the rows fresh and takes no lock: the overview must not hold a row
      was = version ? { "fields" => version.snapshot.fetch("fields", {}), "tags" => version.snapshot.fetch("tags", []), "blocks" => version.blocks } : now
      @fields = changed_fields(was, now)
      @blocks = changed_blocks(was.fetch("blocks", []), now.fetch("blocks", []))
      @locales = @changed_locales.to_a.sort
    end

    def none? = fields.empty? && blocks.empty?

    # The live records that would be left without an address if the rows of
    # `record` were published at `now`, as data (`PublicSite::Paths.foresee`:
    # `{ record_type:, record_id:, locale:, path: }`, the record's own among
    # them). Information, never a refusal: the publish dialog words it
    # (Task 7). Empty when nothing differs (publishing nothing takes nothing)
    # and for a record with no time.
    #
    # NEVER FROM A GET, and not part of `Changes.of`, which is cheap and
    # lock-free. This TRIES a publish: it takes the record's ROW LOCK (a
    # colleague's block autosave on that page waits at `lock_owner` for the
    # length of the call) and WRITES inside a savepoint it rolls back (a copy,
    # `public_paths` rows, `media_usages`, the mark), reading every current
    # address twice. It can be one side of a `(locale, path)` wait. So the
    # request that asks is a POST, sent through the write queue when the
    # dialog opens (Task 7), serialised with the tab's own saves.
    def self.lost_addresses(record, now: Time.current)
      return [] if record.published_at.nil? || of(record).none?

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
    # `{ the row's id => the copy's id }` for such pairs, from the two sides
    # in the form a copy stores blocks in. For `changed_blocks` and for the
    # discard, which must agree on which block is which.
    def self.stand_ins(was, now)
      known = now.map { |block| block["id"] }.to_set
      lost = was.reject { |block| known.include?(block["id"]) }
      return {} if lost.empty?

      copied = was.map { |block| block["id"] }.to_set
      stands_for = {}
      # Top-level blocks (the sections among them) before the blocks inside.
      now.reject { |block| copied.include?(block["id"]) }.partition { |block| block["section_id"].nil? }.flatten.each do |block|
        place = [ stands_for.fetch(block["section_id"], block["section_id"]), block["section_column"] ]
        twin = lost.find { |old| old.values_at("section_id", "section_column") == place && same_content?(old, block) } or next
        lost.delete(twin)
        stands_for[block["id"]] = twin["id"]
      end
      stands_for
    end

    def self.same_content?(one, other)
      BLOCK_CONTENT.all? do |name|
        next one[name] == other[name] unless BLOCK_TRANSLATED.include?(name)

        languages_with_text(one[name]) == languages_with_text(other[name])
      end
    end

    private

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
      rows = ContentBlock.where(id: now.map { |block| block["id"] }).index_by(&:id)
      stands_for = self.class.stand_ins(was, now)
      rows = rows.transform_keys { |id| stands_for.fetch(id, id) }
      now = now.map { |block| block.merge("id" => stands_for.fetch(block["id"], block["id"]), "section_id" => stands_for.fetch(block["section_id"], block["section_id"])) }
      before = was.index_by { |block| block["id"] }
      after = now.index_by { |block| block["id"] }
      # A block that changed container is moved whatever the order says, so
      # it takes no part in finding the ones that stayed in place.
      stayed = ->(id) { before[id] && after[id] && before[id].values_at("section_id", "section_column") == after[id].values_at("section_id", "section_column") }
      settled = unmoved(was.map { |block| block["id"] }.select(&stayed), now.map { |block| block["id"] }.select(&stayed))

      entries = now.filter_map do |block|
        id = block["id"]
        old = before[id]
        kind =
          if old.nil? then note_languages(block) && :added
          elsif content_differs?(old, block) then :changed
          elsif old.values_at("section_id", "section_column") != block.values_at("section_id", "section_column") || !settled.include?(id) then :moved
          end
        Block.new(kind:, block: rows.fetch(id)) if kind
      end
      gone = was.reject { |block| after.key?(block["id"]) }
      removed = gone.any? ? Snapshot.blocks_from(version, record).index_by(&:id) : {}
      entries + gone.map { |block| note_languages(block) && Block.new(kind: :removed, block: removed.fetch(block["id"])) }
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
