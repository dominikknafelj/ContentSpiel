module Publishing
  # Returns the rows of a published or scheduled page or post to WHAT IS IN
  # FORCE (drafts spec §4.3: "the current copy"), through the services every
  # other write goes through, so that each rule they hold (validation, media,
  # translation tracking, derived rows, the audit log, live refresh) holds
  # for a discard.
  #
  # THE COPY IN FORCE, NOT THE NEWEST. A change that is scheduled and has not
  # come into force is unpublished too: the discard withdraws it
  # (`Version.withdraw_pending!`) and the rows go back to what the site
  # shows now. A record whose only copy is pending is shown from its rows and
  # has nothing to return to.
  #
  # TAGS ARE REFERENCES, FOLLOWED BY ID, AND NONE IS EVER MADE. A post's tags
  # go back to the ids its copy holds, each under the name that tag has NOW;
  # a list block's filter goes back to the tag the copy recorded, under its
  # present name. A tag deleted since stays deleted and a merged tag stays
  # merged: the standing rule of this work. A merge leaves no difference
  # behind (it rewrites the copies as it rewrites the rows,
  # `Publishing::Version.repoint_tag!`); where a rename or a delete leaves
  # the rows different from the copy (the copy still shows the old name, or
  # a tag that is gone), the discard succeeds, says so (`REMAINS`, the result's
  # `notice`), and the mark STAYS: the difference is visible in the
  # overview and is published, or left, by a person.
  #
  # WHAT COMES BACK is content: the columns `Publishing.content_columns`
  # names (less the bookkeeping), a page's blocks with their order and
  # sections, a post's tags. The slug, the place in the tree and the publish
  # state are immediate and are not touched. TRANSLATION BOOKKEEPING
  # (`translation_sources`, `translation_original_changed_at`) is whatever
  # the save services leave when the text is written back; it is not copied
  # from the copy, and a translation confirmed since the last publish stays
  # confirmed unless the text it was confirmed for goes back
  # (`test/services/publishing/discard_changes_test.rb` pins it).
  #
  # ONLY WHAT DIFFERS IS WRITTEN: a field or a language that is the same in
  # the rows and in the copy is not handed to a service, so a discard asks
  # for no image it does not put back and marks no translation that did not
  # move.
  #
  # BLOCKS ARE RECONCILED BY ID. A block the copy has and the rows have is
  # rewritten where it differs and keeps its id (its notes, its holder). One
  # the rows lost is created again as a NEW block: its notes went with it
  # when it was deleted. (A block created again by an EARLIER discard has
  # another id than the copy's block and is that block all the same:
  # `Changes.stand_ins` pairs the two, here and in the overview.) One the copy does not have is deleted, with its
  # notes (`ContentBlocks::Destroy`). Then every container gets its blocks
  # back in the copy's order.
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
  # One transaction, the record's row lock first (the lock order of every
  # block write: each block service driven here takes the page's row again,
  # which this transaction already holds, and then block rows); a step that
  # fails rolls all of it back. Nothing public moves: the site shows the
  # copy, before and after. Whether another tab holds part of the record is
  # asked by the controller before this runs
  # (`Admin::EditingClaims#refuse_discard_under_hold`), as for every other
  # write: a call with no tab (the console) is not refused.
  class DiscardChanges < ApplicationService
    include ContentBlocks::Structure
    include ShownSchedule

    NOTHING = "There is nothing to discard".freeze
    # What a discard cannot put back: a tag is a reference, not content of
    # the record, and one that was renamed or deleted since the copy was
    # taken stays as it is now (see TAGS in the class comment). Not a merged
    # one: a merge rewrites the copies too and leaves nothing to say.
    REMAINS = "A tag was renamed or deleted since this was published: that difference stays, as unpublished changes".freeze
    PAGE_TRANSLATED = %w[title subtitle meta_title meta_description hero_alt].freeze
    POST_TRANSLATED = %w[title excerpt].freeze
    BLOCK_TRANSLATED = %w[caption alt].freeze

    def initialize(record, shown_pending: NOT_ASKED, actor: Current.actor)
      @record = record
      @shown_pending = shown_pending
      @actor = actor
    end

    def call
      refused = AccessControl::OwnerRule.refusal(@record) { |key| authorize!(key, @record) }
      return denied(refused, @record) if refused

      @wrote = @moved = @remains = false
      done = @record.class.transaction(requires_new: true) do
        lock_owner(@record)
        @record.reload
        now = Time.current
        version = @record.published_at.nil? ? nil : Publishing.current(@record, now: now)
        next false if version.nil?
        # A scheduled change the dialog did not mention would go with it (`ShownSchedule`).
        next @moved = true if schedule_moved?(@record, now)

        # Nothing differs and nothing is scheduled: a mark left by typing
        # and typing back is cleared, and no event says a discard happened.
        if Changes.new(@record, version).none? && Publishing.pending(@record, now: now).nil?
          Publishing.clear_changes(@record)
          next false
        end

        @record.is_a?(Page) ? restore_page(version) : restore_post(version)
        withdrawn = Version.withdraw_pending!(@record, now: now).last
        Media::UsageIndex.refresh_published(@record, now: now) if withdrawn
        # THE MARK FOLLOWS WHAT IS TRUE NOW, read again under the lock: gone
        # when the rows are the copy, kept when something could not be put
        # back (`REMAINS`), so that difference can still be seen, published
        # or left, and never goes public unseen with a later publish.
        @remains = !Changes.new(@record, version).none?
        @remains ? Publishing.note_change(@record, now: now) : Publishing.clear_changes(@record)
        # Nothing was written and nothing withdrawn: what differs is only
        # what cannot be put back. No event says a discard happened.
        next false unless @wrote || withdrawn

        record_event("#{@record.is_a?(Page) ? "page" : "post"}.changes_discarded", subject: @record, coalesce: false,
          metadata: { "number" => version.number, "withdrawn_number" => withdrawn }.compact)
        true
      end
      return failure(@record, [ MOVED ]) if @moved
      return success(@record, notice: (REMAINS if @remains)) if done

      failure(@record, @errors.presence || [ @remains ? REMAINS : NOTHING ])
    end

    private

    # A step of the discard: another service's result. Its record when it
    # succeeded; otherwise its errors are this service's and everything
    # written so far is rolled back.
    def step(result)
      @wrote = true
      return result.record if result.ok?

      @errors = result.errors
      raise ActiveRecord::Rollback
    end

    def restore_page(version)
      fields = version.snapshot.fetch("fields", {})
      attributes = %w[page_type hero_media_asset_id].select { |name| fields[name] != @record.read_attribute(name) }.to_h { |name| [ name.to_sym, fields[name] ] }
      translations = translations_back(fields, @record, PAGE_TRANSLATED)
      step Pages::Save.call(@record, attributes: attributes, translations: translations, actor: actor) if attributes.any? || translations.any?
      restore_blocks(version.blocks)
    end

    def restore_post(version)
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
      attributes[:tag_names] = tags.map(&:name) unless tags.map(&:id).sort == @record.tags.reload.map(&:id).sort
      step Posts::Save.call(@record, attributes: attributes, translations: translations, actor: actor) if attributes.any? || translations.any?
    end

    # The tags a post's copy holds BY ID (`tag_ids`, which a merge has
    # repointed to the tag that was kept), as the rows they are now: each is
    # attached under whatever name it has today (`Posts::Save` finds it by
    # that name), and an id with no row (the tag was deleted since) is left
    # out. No tag is ever made by a discard.
    def tags_back(version) = Tag.where(id: version.tag_ids).order(:id).to_a

    # A block's settings as the copy has them, with ONE reference followed:
    # a list block's tag filter is a tag's NAME in the settings, and the copy
    # recorded which tag that was (`listed_tag_id`, repointed by a merge).
    # While that tag exists the filter is written under its present name, so
    # the row filters by the tag the published list filters by. When it does
    # not (deleted since), the copy's own name is written: a name no tag has,
    # which lists nothing, as everywhere else. No tag is made.
    def settings_back(attributes)
      settings = attributes["settings"].to_h
      id = attributes["listed_tag_id"] or return settings
      name = Tag.where(id: id).pick(:name) or return settings

      settings.merge("tag" => name)
    end

    def restore_blocks(copied)
      copy_ids = copied.map { |block| block["id"] }
      # A block an earlier discard created again stands for the copy's block
      # it is the same as (`Changes.stand_ins`): it is kept, not deleted and
      # created once more.
      stands_for = Changes.stand_ins(copied, Snapshot.of(@record).fetch("blocks", []))
      extras = ContentBlock.where(owner: @record).where.not(id: copy_ids + stands_for.keys).to_a
      extras.reject(&:container?).each { |block| step ContentBlocks::Destroy.call(block, actor: actor) }
      extras.select(&:container?).each { |block| step ContentBlocks::Destroy.call(block.reload, keep_blocks: true, actor: actor) }

      rows = ContentBlock.where(owner: @record).index_by { |row| stands_for.fetch(row.id, row.id) }
      ids = {} # a copy's block id => the id of the row that stands for it now
      sections, others = copied.partition { |block| BlockTypes.find(block["block_type"])&.capability?(:container) }
      (sections + others).each do |attributes|
        row = rows[attributes["id"]]
        ids[attributes["id"]] = (row ? rewrite(row, attributes) : recreate(attributes, ids)).id
      end

      place(copied, ids)
    end

    # A block both sides have: what differs is written, the rest is left. A
    # change of type is written too (no screen changes a block's type, but a
    # token can).
    def rewrite(row, attributes)
      changed = {}
      changed[:block_type] = attributes["block_type"] unless attributes["block_type"] == row.block_type
      changed[:media_asset_id] = attributes["media_asset_id"] unless attributes["media_asset_id"] == row.media_asset_id
      settings = settings_back(attributes)
      changed[:settings] = every_key(settings, row.settings) unless settings == row.settings.to_h
      translations = block_translations(attributes, row)
      return row if changed.empty? && translations.empty?

      step ContentBlocks::Save.call(row, attributes: changed, translations: translations, actor: actor)
    end

    def recreate(attributes, ids)
      placement = { section_id: ids[attributes["section_id"]], section_column: attributes["section_column"] }.compact
      step ContentBlocks::Save.call(ContentBlock.new(owner: @record),
        attributes: { block_type: attributes["block_type"], media_asset_id: attributes["media_asset_id"], settings: settings_back(attributes), **placement },
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
