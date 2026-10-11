# app/models/publishing/snapshot.rb
module Publishing
  # Builds a copy's data from the rows (`of`) and read-only objects back from
  # a copy (`rebuild`, `blocks_from`), so that the public templates and
  # components draw a copy exactly as they draw rows.
  #
  # A REBUILT RECORD is the row as it is now (id, slug, tree, `published_at`:
  # what a copy does not hold) with the copy's content columns written over
  # it; a page's blocks are its loaded `content_blocks`, a post's tags its
  # loaded `tags`. Reading the collection reads the copy. A SCOPE on it
  # (`page.content_blocks.listing`) would still query the rows: a public
  # reader never calls one (`test/lib/public_readers_test.rb`).
  # A library image is looked up live by the id the copy holds.
  module Snapshot
    module_function

    def of(record)
      data = { "fields" => record.attributes.slice(*Publishing.content_columns(record)).as_json }
      case record
      when Page then data["blocks"] = blocks_of(record)
      when Post then data["tags"] = tags_of(record)
      end
      data
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
      view
    end

    # A copy's blocks as read-only `ContentBlock`s owned by `owner`. A column
    # the copy does not know (added since) keeps the table's default; a key
    # the table does not know (removed since) is ignored.
    def blocks_from(version, owner)
      version.blocks.map do |attributes|
        block = ContentBlock.instantiate(ContentBlock.column_defaults.merge("id" => attributes["id"]))
        attributes.each { |name, value| block.write_attribute(name, value) if name != "id" && block.has_attribute?(name) }
        block.clear_changes_information
        block.listed_tag_id = attributes["listed_tag_id"] if attributes.key?("listed_tag_id")
        block.association(:owner).target = owner
        block.readonly!
        block
      end
    end

    def tags_from(version)
      version.snapshot.fetch("tags", []).map do |tag|
        Tag.instantiate(Tag.column_defaults.merge("id" => tag["id"], "name" => tag["name"])).tap(&:readonly!)
      end
    end

    # Every block of the page, read fresh (an association may be stale inside
    # the save that publishes), in reading order. A list block also records
    # the tag its filter names, by id (`ContentBlock#listed_tag_id`).
    def blocks_of(page)
      BlockOutline.new(ContentBlock.where(owner: page).to_a).reading_order.map do |block|
        attributes = block.attributes.as_json
        attributes["listed_tag_id"] = block.listed_tag_id if block.definition&.capability?(:lists_posts)
        attributes
      end
    end

    def tags_of(post)
      Tag.where(id: PostTag.where(post_id: post.id).select(:tag_id)).order(:id).pluck(:id, :name).map { |id, name| { "id" => id, "name" => name } }
    end
  end
end
