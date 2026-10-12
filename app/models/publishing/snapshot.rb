module Publishing
  # Builds a copy's data from the rows (`of`) and read-only objects back from
  # a copy (`rebuild`, `blocks_from`), so that the public templates and
  # components draw a copy exactly as they draw rows.
  #
  # A REBUILT RECORD is the row as it is now (id, slug, tree, `published_at`:
  # what a copy does not hold) with the copy's content columns written over
  # it; a page's blocks are its loaded `content_blocks`, a post's tags its
  # loaded `tags`. Reading the collection reads the copy. A SCOPE on it
  # (`page.content_blocks.listing`) would still query the rows, and read the
  # ROWS: a public reader never calls one. Likewise `block.section` reads the
  # copy's section (`blocks_from` sets it), but `page.children`,
  # `self_and_ancestors` and `root?` read the live tree, by design.
  # A library image is looked up live by the id the copy holds.
  #
  # WHAT A REBUILT OBJECT CANNOT DO (`Rebuilt`): write, delete, touch, lock or
  # reload itself, and write or reload its loaded collections (`<<`, `create`,
  # `delete_all`, `clear`, `tags=`, `reload`...): each raises
  # `ActiveRecord::ReadOnlyRecord`. WHAT REMAINS POSSIBLE: a relation built
  # from the class (`Page.where(id: view.id).update_all`), a scope on a
  # collection (`view.content_blocks.where(...)`, which also READS rows),
  # raw SQL, a write through an association that was NOT loaded at rebuild
  # time (only the loaded collections are guarded: `view.published_versions
  # .delete_all`, `view.children.create`, `post_view.post_tags.delete_all`,
  # and, after `rebuild(..., with_blocks: false)`, `view.content_blocks
  # .create` / `.delete_all`, which also read the rows), and an in-memory change to an attribute (it is never saved, but
  # `view.title = "x"` is not refused); and a rebuilt record is `==` and
  # `hash`-equal to its row (same class and id), so a hash keyed by one finds
  # the other. Never hand a rebuilt object to a service.
  module Snapshot
    module_function

    # Raises for every method of a record that writes it or turns it back into
    # the rows. Extended onto the object itself (the singleton comes before
    # the class), so Rails' own definitions are never reached.
    module Rebuilt
      WRITERS = %i[
        save save! update update! update_attribute update_attribute! update_column update_columns touch
        delete destroy destroy! reload lock! with_lock increment! decrement! toggle!
      ].freeze

      WRITERS.each do |name|
        define_method(name) { |*, **, &| raise ActiveRecord::ReadOnlyRecord, "#{self.class.name} ##{id} is rebuilt from a published copy: it cannot #{name}" }
      end
    end

    # The same for a loaded association of a rebuilt object.
    module RebuiltCollection
      WRITERS = %i[
        writer ids_writer concat concat_records delete_all destroy_all delete destroy create create! build
        replace reload reset reset_scope
      ].freeze

      WRITERS.each do |name|
        define_method(name) { |*, **, &| raise ActiveRecord::ReadOnlyRecord, "a collection of a rebuilt record cannot #{name}" }
      end
    end

    # The copy's data. The record is READ FROM ITS ROW, fresh (`row:` when the
    # caller has just locked it: only the copy-taking method locks), never from the
    # object in memory or a loaded association, which may be older than a
    # colleague's committed save. This method takes NO lock: the overview of
    # the publish dialog calls it on a request that must not hold a page's
    # row against its editors (a POST since the dialog's overview moved
    # through the write queue, `Admin::PublishingController#changes`).
    #
    # `uncached`: inside a request Rails answers a repeated SELECT from its
    # query cache, and a row, a page's blocks or a post's tags read earlier
    # in the request (before a colleague's commit) would come back as they
    # were. (A locking read is never cached; these reads would be.)
    def of(record, row: nil)
      ActiveRecord::Base.uncached do
        row ||= record.class.unscoped.find(record.id)
        data = { "fields" => row.attributes.slice(*Publishing.content_columns(row)).as_json }
        case row
        when Page then data["blocks"] = blocks_of(row)
        when Post then data["tags"] = tags_of(row)
        end
        data
      end
    end

    def lists_posts?(data)
      data.fetch("blocks", []).any? { |block| BlockTypes.find(block["block_type"])&.capability?(:lists_posts) }
    end

    def rebuild(version, record, with_blocks: true)
      view = record.class.instantiate(record.attributes_for_database)
      version.snapshot.fetch("fields", {}).each { |name, value| view.write_attribute(name, value) if view.has_attribute?(name) }
      view.clear_changes_information
      view.published_version = version
      case view
      when Page then view.association(:content_blocks).target = blocks_from(version, view) if with_blocks
      when Post then view.association(:tags).target = tags_from(version)
      end
      view.readonly!
      view.extend(Rebuilt)
      view.class.reflect_on_all_associations.each do |reflection|
        association = view.association(reflection.name)
        association.extend(RebuiltCollection) if association.loaded? && reflection.collection?
      end
      view
    end

    # A copy's blocks as read-only `ContentBlock`s owned by `owner`, each with
    # its section from the same copy. A column the copy does not know (added
    # since) keeps the table's default; a key the table does not know
    # (removed since) is ignored.
    def blocks_from(version, owner)
      blocks = version.blocks.map do |attributes|
        block = ContentBlock.instantiate(ContentBlock.column_defaults.merge("id" => attributes["id"]))
        attributes.each { |name, value| block.write_attribute(name, value) if name != "id" && block.has_attribute?(name) }
        block.clear_changes_information
        block.listed_tag_id = attributes["listed_tag_id"] if attributes.key?("listed_tag_id")
        block.association(:owner).target = owner
        block.readonly!
        block.extend(Rebuilt)
        block
      end
      by_id = blocks.index_by(&:id)
      blocks.each { |block| block.association(:section).target = by_id[block.section_id] if by_id.key?(block.section_id) }
      blocks
    end

    def tags_from(version)
      version.snapshot.fetch("tags", []).map do |tag|
        Tag.instantiate(Tag.column_defaults.merge("id" => tag["id"], "name" => tag["name"])).tap { |built| built.readonly!; built.extend(Rebuilt) }
      end
    end

    # Every block of the page, read fresh (an association may be stale inside
    # the save that publishes), in reading order. A list block also records
    # the tag its filter names, by id (`ContentBlock#listed_tag_id`).
    def blocks_of(page)
      columns = Publishing.content_columns(ContentBlock)
      BlockOutline.new(ContentBlock.where(owner: page).to_a).reading_order.map do |block|
        attributes = block.attributes.slice(*columns).as_json
        attributes["listed_tag_id"] = block.listed_tag_id if block.definition&.capability?(:lists_posts)
        attributes
      end
    end

    def tags_of(post)
      Tag.where(id: PostTag.where(post_id: post.id).select(:tag_id)).order(:id).pluck(:id, :name).map { |id, name| { "id" => id, "name" => name } }
    end
  end
end
