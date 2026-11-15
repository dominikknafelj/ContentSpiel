module SiteSearch
  # A tag's listing page (search spec §4.4): where a tag suggestion goes.
  # The public site has no tag page and no tag route; a tag is listed by a
  # list block (a `:lists_posts` type) filtered by it, whose copy records the
  # tag by id (`Publishing::Snapshot.blocks_of`: `listed_tag_id`). So a tag's
  # page is the first page in reading order that a visitor of `locale` can
  # reach (`SiteSearch::FirstHolder`) whose copy in force holds such a block
  # with that `listed_tag_id` and NO CONTENT TYPE: a list that also names a
  # type lists only some of the tag's posts, so it is not the tag's listing.
  #
  # Read from the copies in force and never from the rows, as `SearchPage`:
  # a list an editor placed and did not publish, or one on a draft or
  # trashed page, is no tag's page. A tag with none is left out of the
  # answer, and its suggestion is a search for it.
  #
  # THE STATEMENTS, whatever the number of tags: the copies that hold a list
  # of one of them, then `FirstHolder`'s (the rows, the visibility rule's,
  # the addresses, the tree's order, once for every tag) and the copies of
  # the pages found.
  module TagPage
    module_function

    # `{ tag id => page as published }`, a read-only view rebuilt from its
    # copy, without its blocks, for each of `tag_ids` that has a listing.
    def for(tag_ids, locale:, now:)
      tag_ids = tag_ids.uniq
      names = BlockTypes.with_capability(:lists_posts).map { |type| type.name.to_s }
      return {} if tag_ids.empty? || names.empty?

      listing = listings_of(tag_ids, names, now)
      holder = FirstHolder.new(listing.values.flatten, now: now, locale: locale)
      firsts = listing.filter_map { |tag_id, ids| (row = holder.first(ids)) && [ tag_id, row ] }.to_h
      views = Publishing.published_all(firsts.values.uniq, now: now).index_by(&:id)
      firsts.transform_values { |row| views.fetch(row.id) }
    end

    # `{ tag id => [page id, …] }`: the pages whose copy in force holds a
    # list of the tag with no content type. The containment finds the copies
    # with a list of one of the tags; that the list names no content type is
    # read from those copies' blocks, since a blank and an absent type are
    # both "every type" (`BlockTypes::PostList.listed_posts`).
    def listings_of(tag_ids, names, now)
      blocks = Publishing::Version.arel_table[:blocks]
      holding = names.product(tag_ids).map { |name, tag_id| SqlNodes.json_contains(blocks, [ { "block_type" => name, "listed_tag_id" => tag_id } ]) }.reduce(:or)
      wanted = tag_ids.to_set
      FirstHolder.copies_holding(holding, now: now).pluck(:record_id, :blocks).each_with_object(Hash.new { |all, key| all[key] = [] }) do |(page_id, copy_blocks), all|
        copy_blocks.each do |block|
          next unless names.include?(block["block_type"]) && wanted.include?(block["listed_tag_id"])
          next if block.dig("settings", "content_type").present?

          all[block["listed_tag_id"]] << page_id
        end
      end
    end

    private_class_method :listings_of
  end
end
