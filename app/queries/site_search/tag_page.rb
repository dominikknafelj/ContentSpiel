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
  # of one of them (and, through `with_search_page`, a Search block), then
  # `FirstHolder`'s (the rows, the visibility rule's, the addresses, the
  # tree's order, once for every tag and the search page together) and the
  # copies of the pages found.
  module TagPage
    module_function

    # `{ tag id => page as published }`, a read-only view rebuilt from its
    # copy, without its blocks, for each of `tag_ids` that has a listing.
    def for(tag_ids, locale:, now:) = read(tag_ids, locale: locale, now: now, search: false).first

    # `[for(tag_ids), SearchPage#page]` in the statements of one: a tag
    # suggestion goes to its listing page, else to a search for it on the
    # search page, and both are first holders of a kind of block, so one
    # read of the copies and one `FirstHolder` answer both.
    def with_search_page(tag_ids, locale:, now:) = read(tag_ids, locale: locale, now: now, search: true)

    def read(tag_ids, locale:, now:, search:)
      tag_ids = tag_ids.uniq
      names = BlockTypes.with_capability(:lists_posts).map { |type| type.name.to_s }
      listing_condition = holding(tag_ids, names) unless tag_ids.empty? || names.empty?
      search_condition = SearchPage.holding if search
      return [ {}, nil ] unless listing_condition || search_condition

      listing, searching = holders(listing_condition, search_condition, tag_ids, names, now)
      holder = FirstHolder.new([ *listing.values.flatten, *searching ], now: now, locale: locale)
      firsts = listing.filter_map { |tag_id, ids| (row = holder.first(ids)) && [ tag_id, row ] }.to_h
      search_row = holder.first(searching) unless searching.empty?
      views = Publishing.published_all([ *firsts.values, search_row ].compact.uniq, now: now).index_by(&:id)
      [ firsts.transform_values { |row| views.fetch(row.id) }, search_row && views.fetch(search_row.id) ]
    end

    # The containment that finds the copies with a list of one of the tags.
    def holding(tag_ids, names)
      blocks = Publishing::Version.arel_table[:blocks]
      names.product(tag_ids).map { |name, tag_id| SqlNodes.json_contains(blocks, [ { "block_type" => name, "listed_tag_id" => tag_id } ]) }.reduce(:or)
    end

    # `[{ tag id => [page id, …] }, [page id, …]]`: the pages whose copy in
    # force holds a list of the tag with no content type, and those holding a
    # Search block, in one statement that reads a copy's blocks only when it
    # holds a list. That the list names no content type is read from those
    # blocks, since a blank and an absent type are both "every type"
    # (`BlockTypes::PostList.listed_posts`).
    def holders(listing_condition, search_condition, tag_ids, names, now)
      blocks = Publishing::Version.arel_table[:blocks]
      listed = listing_condition ? Arel::Nodes::Case.new.when(listing_condition).then(blocks) : Arel::Nodes.build_quoted(nil)
      searched = search_condition ? Arel::Nodes::Grouping.new(search_condition) : Arel::Nodes.build_quoted(false)
      wanted = tag_ids.to_set
      listing = Hash.new { |all, key| all[key] = [] }
      searching = []
      FirstHolder.copies_holding([ listing_condition, search_condition ].compact.reduce(:or), now: now).pluck(:record_id, listed, searched).each do |page_id, copy_blocks, holds_search|
        searching << page_id if holds_search
        (copy_blocks || []).each do |block|
          next unless names.include?(block["block_type"]) && wanted.include?(block["listed_tag_id"])
          next if block.dig("settings", "content_type").present?

          listing[block["listed_tag_id"]] << page_id
        end
      end
      [ listing, searching ]
    end

    private_class_method :read, :holding, :holders
  end
end
