module Publishing
  # Writes a page's or a post's rows back to the content of one of its
  # copies (`return_to!(version)`), through the services every other write
  # goes through, so that each rule they hold (validation, media,
  # translation tracking, derived rows, the audit log, live refresh) holds
  # for it. `Publishing::DiscardChanges` returns to the copy in force; a
  # restore returns to any version.
  #
  # IT IS THE RECONCILIATION AND NOTHING AROUND IT. The including service
  # (which includes `ContentBlocks::Structure` too) opens the transaction,
  # takes `lock_owner(record)` and reloads the record before calling it, and
  # decides the rest itself: this touches no copy and no pending copy, sets
  # and clears no mark (the save services leave theirs) and records no event
  # of its own. Each write is a STEP (`#step`): another service's result,
  # whose failure leaves its errors in `@errors` and raises
  # `ActiveRecord::Rollback` out of the caller's transaction block, so
  # everything written so far goes; `@wrote` says whether any step ran.
  #
  # TAGS ARE REFERENCES, FOLLOWED BY ID, AND NONE IS EVER MADE. A post's tags
  # go back to the ids its copy holds, each under the name that tag has NOW;
  # a list block's filter goes back to the tag the copy recorded, under its
  # present name. A tag deleted since stays deleted (and is counted,
  # `Outcome#tags_missing`) and a merged tag stays merged. A merge leaves no
  # difference behind (it rewrites the copies as it rewrites the rows,
  # `Publishing::Version.repoint_tag!`); a rename or a delete leaves the rows
  # different from the copy, which the caller tells a person about.
  #
  # IMAGES ARE REFERENCES TOO, AND ONE THAT WENT IS LEFT EMPTY. A copy names
  # library images by id. One in force or pending is protected
  # (`Media::UsageIndex`, role `published`), but an older version's image
  # may since be in the trash or deleted. The hero and an image block's
  # image come back while the image is in the library and not in the trash
  # (`Media::Asset.kept`, the rule `Media::Choosing` refuses by); otherwise
  # they are written empty and counted (`Outcome#images_missing`), so no id
  # that names nothing reaches a NO ACTION foreign key and no trashed image
  # is chosen again. An image inside rich text is left as stored: a body may
  # keep a dead reference (`Media::UsageIndex#rich_text_rows`), which renders
  # nothing, as a rebuilt copy does.
  #
  # WHAT COMES BACK is content: the columns `Publishing.content_columns`
  # names (less the bookkeeping), a page's blocks with their order and
  # sections, a post's tags. The slug, the place in the tree and the publish
  # state are immediate and are not touched. TRANSLATION BOOKKEEPING
  # (`translation_sources`, `translation_original_changed_at`) is whatever
  # the save services leave when the text is written back; it is not copied
  # from the copy, and a translation confirmed since stays confirmed unless
  # the text it was confirmed for goes back
  # (`test/services/publishing/discard_changes_test.rb` pins it).
  #
  # ONLY WHAT DIFFERS IS WRITTEN: a field or a language that is the same in
  # the rows and in the copy is not handed to a service, so a return asks
  # for no image it does not put back and marks no translation that did not
  # move.
  #
  # BLOCKS ARE RECONCILED BY ID. A block the copy has and the rows have is
  # rewritten where it differs and keeps its id (its notes, its holder). One
  # the rows lost is created again as a NEW block: its notes went with it
  # when it was deleted. (A block created again by an EARLIER return has
  # another id than the copy's block and is that block all the same, also
  # when it was made without an image that went: `Changes.stand_ins` pairs
  # the two, here and in the overview.) One the
  # copy does not have is deleted, with its notes (`ContentBlocks::Destroy`).
  # Then every container gets its blocks back in the copy's order.
  #
  # THE ORDER, and why. (1) What the copy does not have goes first: plain
  # blocks, then sections with `keep_blocks`, which lifts to the top level
  # whatever of the copy's blocks someone put into them. (2) Sections before
  # the blocks in them: a section's layout must be the copy's before a block
  # is put back into its third column, and a section that was deleted must
  # exist before its blocks are created in it. (3) Places last, the top
  # level before the columns, each through `ContentBlocks::Reorder`, the one
  # service that moves a block between containers.
  #
  # LOCKS: the caller's `lock_owner` holds the settings row and the record's
  # row; each block service driven here takes the page's row again, which
  # the transaction already holds, and then block rows (the lock order of
  # every block write, `ContentSpiel::LockOrder`).
  module ReturnTo
    # What could not be brought back, as counts: library images that are
    # gone or in the trash (each once, left empty wherever named), and tags
    # deleted since (a post's, left out; a list filter's, naming no tag).
    Outcome = Data.define(:images_missing, :tags_missing)

    # What a return cannot put back: a tag is a reference, not content of
    # the record, and one that was renamed or deleted since the copy was
    # taken stays as it is now (TAGS above). Not a merged one: a merge
    # rewrites the copies too and leaves nothing to say.
    REMAINS = "A tag was renamed or deleted since this was published: that difference stays, as unpublished changes".freeze
    # An image is a reference too: one deleted or moved to the trash since
    # the copy was taken is left empty, never pointed at (IMAGES above).
    IMAGES_GONE = "An image was deleted or moved to the trash since this was published: it is left empty, as unpublished changes".freeze

    PAGE_TRANSLATED = %w[title subtitle meta_title meta_description hero_alt].freeze
    POST_TRANSLATED = %w[title excerpt].freeze
    BLOCK_TRANSLATED = %w[caption alt].freeze

    private

    def return_to!(version)
      @wrote = @denied = false
      @tags_missing = 0
      @gone_images = Set.new
      @kept_images = kept_images(version)
      @record.is_a?(Page) ? return_page(version) : return_post(version)
      Outcome.new(images_missing: @gone_images.size, tags_missing: @tags_missing)
    end

    # The sentences for what stays different after the return, given the
    # rows compared with the copy returned to: an image that went
    # (`IMAGES_GONE`), and a tag (`REMAINS`) when one was deleted or when
    # anything else still differs, which is a rename (a post's tags, a list
    # block's filter): the return puts back all but those.
    def left_behind(outcome, changes)
      return [] if changes.none?

      [ (IMAGES_GONE if outcome.images_missing.positive?),
        (REMAINS if outcome.tags_missing.positive? || beyond_gone_images?(changes)) ].compact
    end

    # Whether the rows differ from the copy in more than the images that
    # went: the hero the copy names and a block whose only difference is
    # that its gone image is empty (made again without it, it stands for
    # the copy's block, `Changes.stand_ins`) do not count.
    def beyond_gone_images?(changes)
      fields = changes.fields
      fields -= %w[hero_media_asset_id] if gone_image?(changes.sides.first.fetch("fields", {})["hero_media_asset_id"])
      return true if fields.any?

      changes.blocks.any? do |entry|
        was, now = changes.sides_of(entry)
        !(entry.kind == :changed && gone_image?(was["media_asset_id"]) && now["media_asset_id"].nil? &&
          Changes.same_content?(was.merge("media_asset_id" => nil), now))
      end
    end

    # A step of the return: another service's result. Its record when it
    # succeeded; otherwise its errors are the caller's and everything
    # written so far is rolled back.
    def step(result)
      @wrote = true
      return result.record if result.ok?

      @errors = result.errors
      # A refusal's `access.denied` was written inside the transaction this
      # rollback takes away; `@denied` lets the caller record it again
      # outside (`RestoreVersion`).
      @denied = result.denied?
      raise ActiveRecord::Rollback
    end

    # The kept library images among those the copy names (the hero, every
    # image block's) and those the record's blocks name now, in one
    # statement: the first say what may be written back, both together are
    # what `Changes.stand_ins` pairs blocks by.
    def kept_images(version)
      ids = version.blocks.map { |block| block["media_asset_id"] }
      ids << version.snapshot.fetch("fields", {})["hero_media_asset_id"]
      kept = Media::Asset.kept
      kept.where(id: ids.compact.uniq).or(kept.where(id: ContentBlock.where(owner: @record).select(:media_asset_id))).pluck(:id).to_set
    end

    # Whether a copy's image id names an image that is gone or in the trash.
    def gone_image?(id) = !id.nil? && !@kept_images.include?(id)

    # The copy's image id when it may be written back, else nil; each gone
    # image is counted once, however many places named it.
    def image_back(id)
      return id unless gone_image?(id)

      @gone_images << id
      nil
    end

    # The page's template goes back as the copy names it, whether or not the
    # theme still declares it: the name is carried, not chosen, so the copy's
    # settings count as stored for this save (`Page#carried_settings`).
    def return_page(version)
      fields = version.snapshot.fetch("fields", {})
      attributes = {}
      hero = image_back(fields["hero_media_asset_id"])
      attributes[:hero_media_asset_id] = hero unless hero == @record.hero_media_asset_id
      template = fields["settings"].to_h["template"]
      attributes[:template] = template unless template == @record.template
      @record.carried_settings = fields["settings"]
      translations = translations_back(fields, @record, PAGE_TRANSLATED)
      step Pages::Save.call(@record, attributes: attributes, translations: translations, actor: actor) if attributes.any? || translations.any?
      return_blocks(version.blocks)
    end

    def return_post(version)
      fields = version.snapshot.fetch("fields", {})
      translations = translations_back(fields, @record, POST_TRANSLATED)
      differing(fields["body"], @record.read_attribute(:body)).each do |locale|
        (translations[locale] ||= {})[:body] = fields["body"].to_h[locale] || RichText::Document.empty
      end
      differing(fields["translated_metadata"], @record.translated_metadata).each do |locale|
        (translations[locale] ||= {})[:fields] = every_key(fields["translated_metadata"].to_h[locale], @record.translated_metadata.to_h[locale])
      end
      attributes = {}
      attributes[:fields] = every_key(fields["metadata"], @record.metadata) unless fields["metadata"].to_h == @record.metadata.to_h
      tags = tags_back(version)
      @tags_missing += version.tag_ids.uniq.size - tags.size
      attributes[:tag_names] = tags.map(&:name) unless tags.map(&:id).sort == @record.tags.reload.map(&:id).sort
      step Posts::Save.call(@record, attributes: attributes, translations: translations, actor: actor) if attributes.any? || translations.any?
    end

    # The tags a post's copy holds BY ID (`tag_ids`, which a merge has
    # repointed to the tag that was kept), as the rows they are now: each is
    # attached under whatever name it has today (`Posts::Save` finds it by
    # that name), and an id with no row (the tag was deleted since) is left
    # out. No tag is ever made.
    def tags_back(version) = Tag.where(id: version.tag_ids).order(:id).to_a

    # A block's settings as the copy has them, with ONE reference followed:
    # a list block's tag filter is a tag's NAME in the settings, and the copy
    # recorded which tag that was (`listed_tag_id`, repointed by a merge).
    # While that tag exists the filter is written under its present name, so
    # the row filters by the tag the copy's list filters by. When it does
    # not (deleted since, counted), the copy's own name is written: a name no
    # tag has, which lists nothing, as everywhere else. No tag is made.
    def settings_back(attributes)
      settings = attributes["settings"].to_h
      id = attributes["listed_tag_id"] or return settings
      name = Tag.where(id: id).pick(:name)
      return settings.merge("tag" => name) if name

      @tags_missing += 1
      settings
    end

    def return_blocks(copied)
      copy_ids = copied.map { |block| block["id"] }
      # A block an earlier return created again stands for the copy's block
      # it is the same as (`Changes.stand_ins`): it is kept, not deleted and
      # created once more.
      stands_for = Changes.stand_ins(copied, Snapshot.of(@record).fetch("blocks", []), kept_images: @kept_images)
      extras = ContentBlock.where(owner: @record).where.not(id: copy_ids + stands_for.keys).to_a
      extras.reject(&:container?).each { |block| step ContentBlocks::Destroy.call(block, actor: actor) }
      extras.select(&:container?).each { |block| step ContentBlocks::Destroy.call(block.reload, keep_blocks: true, actor: actor) }

      rows = ContentBlock.where(owner: @record).index_by { |row| stands_for.fetch(row.id, row.id) }
      release_changed_anchors(rows, copied)
      ids = {} # a copy's block id => the id of the row that stands for it now
      sections, others = copied.partition { |block| BlockTypes.find(block["block_type"])&.capability?(:container) }
      (sections + others).each do |attributes|
        row = rows[attributes["id"]]
        ids[attributes["id"]] = (row ? rewrite(row, attributes) : recreate(attributes, ids)).id
      end

      place(copied, ids)
    end

    # A section's anchor is unique on the page and the sections are returned
    # one at a time, so writing one section's anchor while another row still
    # holds it would be refused. Every anchor that differs from the copy's is
    # cleared first (under the page lock the caller holds); each copy anchor
    # is then written back onto a free name.
    def release_changed_anchors(rows, copied)
      copied.each do |attributes|
        row = rows[attributes["id"]]
        next unless row&.container? && row.settings["anchor"].present?
        next if row.settings["anchor"] == attributes["settings"].to_h["anchor"]

        step ContentBlocks::Save.call(row, attributes: { settings: { "anchor" => nil } }, actor: actor)
      end
    end

    # A block both sides have: what differs is written, the rest is left. A
    # change of type is written too (no screen changes a block's type, but a
    # token can).
    #
    # A block's choice names (a section's style) go back as the copy has
    # them, as the page's template does: carried, so a name the theme no
    # longer declares is written back and not refused (`carried_settings`),
    # here and for a block made again.
    def rewrite(row, attributes)
      changed = {}
      changed[:block_type] = attributes["block_type"] unless attributes["block_type"] == row.block_type
      image = image_back(attributes["media_asset_id"])
      changed[:media_asset_id] = image unless image == row.media_asset_id
      settings = settings_back(attributes)
      changed[:settings] = every_key(settings, row.settings) unless settings == row.settings.to_h
      translations = block_translations(attributes, row)
      return row if changed.empty? && translations.empty?

      row.carried_settings = settings
      step ContentBlocks::Save.call(row, attributes: changed, translations: translations, actor: actor)
    end

    def recreate(attributes, ids)
      placement = { section_id: ids[attributes["section_id"]], section_column: attributes["section_column"] }.compact
      settings = settings_back(attributes)
      block = ContentBlock.new(owner: @record).tap { |fresh| fresh.carried_settings = settings }
      step ContentBlocks::Save.call(block,
        attributes: { block_type: attributes["block_type"], media_asset_id: image_back(attributes["media_asset_id"]), settings: settings, **placement },
        translations: block_translations(attributes, nil), actor: actor)
    end

    def block_translations(attributes, row)
      translations = translations_back(attributes, row, BLOCK_TRANSLATED)
      differing(attributes["body"], row&.read_attribute(:body)).each do |locale|
        (translations[locale] ||= {})[:body] = attributes["body"].to_h[locale] || RichText::Document.empty
      end
      differing(attributes["translated_settings"], row&.translated_settings).each do |locale|
        (translations[locale] ||= {})[:settings] = every_key(attributes["translated_settings"].to_h[locale], row&.translated_settings.to_h[locale])
      end
      translations
    end

    # Each container's blocks back in the copy's order: the top level first,
    # then each column. A block that stands in a container where it does not
    # belong is listed last there until its own container's turn takes it
    # away: `Reorder` wants every member of the container it writes named
    # (`Reorder#refusal`: the order is the members plus the announced
    # arrivals, each once, and each arrival is where `moved_from` says). The
    # rows are read again for every container, since the one before moved
    # some.
    def place(copied, ids)
      containers = copied.group_by { |block| [ ids[block["section_id"]], block["section_column"] ] }
      containers.sort_by { |(section_id, column), _| [ section_id ? 1 : 0, section_id.to_i, column.to_i ] }.each do |(section_id, column), blocks|
        now = ContentBlock.where(owner: @record).reorder(:position, :id).pluck(:id, :section_id, :section_column)
        wanted = blocks.map { |block| ids.fetch(block["id"]) }
        members = now.select { |_, section, col| section == section_id && col == column }.map(&:first)
        arriving = now.select { |id, section, col| wanted.include?(id) && [ section, col ] != [ section_id, column ] }
          .to_h { |id, section, col| [ id, { section_id: section, column: col } ] }
        ordered = wanted + (members - wanted)
        next if arriving.empty? && members == ordered

        step ContentBlocks::Reorder.call(@record, ordered, section: section_id, column: column, moved_from: arriving, actor: actor)
      end
    end

    # `{ locale => { name: the copy's value } }` for every language and plain
    # translated column in which the rows differ from the copy; a language
    # the rows gained since is emptied again.
    def translations_back(copy, row, names)
      names.each_with_object({}) do |name, translations|
        differing(copy[name], row&.read_attribute(name)).each do |locale|
          (translations[locale] ||= {})[name.to_sym] = copy[name].to_h[locale]
        end
      end
    end

    # The languages in which two per-language values differ, judged as the
    # overview judges it (`Changes.languages_with_text`): a blank, an empty
    # document and a missing language are the same.
    def differing(copy, rows)
      copy = Changes.languages_with_text(copy)
      rows = Changes.languages_with_text(rows)
      (copy.keys | rows.keys).select { |locale| copy[locale] != rows[locale] }
    end

    # `copy`'s values under every key either side has: a key only the rows
    # have is given back as nil, since these services assign what they are
    # handed and leave the rest.
    def every_key(copy, rows)
      copy = copy.to_h
      (copy.keys | rows.to_h.keys).index_with { |key| copy[key] }
    end
  end
end
