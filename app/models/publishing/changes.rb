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
  # in a copy so that a discard can put them back, and say nothing a person
  # edited.
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
      now = Snapshot.of(record) # reads the rows fresh and takes no lock: this runs on a GET
      was = version ? { "fields" => version.snapshot.fetch("fields", {}), "tags" => version.snapshot.fetch("tags", []), "blocks" => version.blocks } : now
      @fields = changed_fields(was, now)
      @blocks = changed_blocks(was.fetch("blocks", []), now.fetch("blocks", []))
      @locales = @changed_locales.to_a.sort
    end

    def none? = fields.empty? && blocks.empty?

    # The live records that would be left without an address if these rows
    # were published now, as data (`PublicSite::Paths.foresee`:
    # `{ record_type:, record_id:, locale:, path: }`, the record's own among
    # them). Information, never a refusal: the publish dialog words it
    # (Task 7). Asked for, not computed with the rest: it tries a publish in
    # a savepoint and reads every current address twice, which a page view
    # or a list must never pay, and `PublishChanges` asks only whether
    # anything differs. Empty when nothing differs, since publishing
    # nothing takes nothing.
    def lost_addresses
      @lost_addresses ||= (none? || record.published_at.nil?) ? [] : PublicSite::Paths.foresee(record)
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

      before = before.is_a?(Hash) ? before.compact_blank : {}
      after = after.is_a?(Hash) ? after.compact_blank : {}
      (before.keys | after.keys).select { |locale| before[locale] != after[locale] }.each { |locale| @changed_locales << locale }.any?
    end

    def changed_blocks(was, now)
      before = was.index_by { |block| block["id"] }
      after = now.index_by { |block| block["id"] }
      rows = ContentBlock.where(id: after.keys).index_by(&:id)
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
