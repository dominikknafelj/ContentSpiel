# Which page lists what (pages in the mind graph, spec §1, decisions 9 and
# 10): the "lists" lines, and the posts behind them.
#
# A LINE IS MADE FROM THE BLOCK, NEVER FROM THE POSTS. For each list block
# (a block whose type has the `lists_posts` capability; in a section or not,
# its owner is the page) of the pages handed in, its typed settings say the
# target: the tag when it names one (found by name whatever the case, as the
# listing finds it; a name no tag has makes no line, as it lists nothing),
# else the content type, else the one "All posts" node. One line per distinct
# target of a page. Two tags whose names differ only in case (an old row, a
# write around the model) are one name to the listing, so they are one
# target here, the tag of the lower id, and the posts of both are listed.
#
# WHICH POSTS A PAGE LISTS is worked out here in Ruby, from rows the caller
# has loaded, by asking `BlockTypes::PostList.matches?` -- the listing's own
# criteria -- so the graph cannot come to disagree with the public page and
# with a post's address (`test/queries/post_graph/listings_test.rb` holds
# the parity). Blocks with the same settings share one pass over the posts.
#
# WHICH TARGET BRINGS A POST IN (`target_of`): the first list block of the
# page, AS A PERSON READS THE PAGE (`blocks`, by `BlockOutline`: never by
# id or by `position` alone), that has a target and lists the post. A page's
# local view draws a faint line from that hub to the post (pages spec §1,
# the third design answers), so a post has one such line however many
# blocks of the page list it.
#
# It knows nothing of rights: `page_ids` and `post_rows` are what the viewer
# may read, narrowed by the caller, so "listed" means "a page YOU can read
# lists it" (spec §2, Risks).
#
# Two statements: the blocks (with the sections that place them), and the
# tags their settings name. (With no
# name to look up the second is not made: `Tag.named_any` answers `none`.)
#
# THE WORK IN RUBY IS BOUNDED TOO, and by counts a test holds, since no
# statement shows it (measured on 2026-10-13 at 200 pages and 2,000 posts,
# the spec's "As built"; every read of the graph loads the site, so this
# runs on each of them):
# - The posts are put in order ONCE (`@ordered`, newest first), so a list
#   made by one pass over them is in order already and nothing sorts 2,000
#   posts per page. As first built each page's posts were sorted for that
#   page by a two-part key: 200 pages listing everything took 0.58 s.
# - `matches?` is asked once per distinct filter and distinct KIND of post
#   (`@kinds`: a stored type with the named tags it carries), not once per
#   post: it answers from those two alone, so posts of one kind share the
#   answer. 200 pages each with a filter of its own were 400,000 calls
#   (0.89 s).
# - Pages whose blocks say the same share one list (`listed_by`), frozen.
module PostGraph
  class Listings
    # The list blocks of these pages, page by page, each page's IN THE ORDER
    # A PERSON READS THEM: `BlockOutline#reading_order`, the one rule for
    # that (top-level blocks by position, a section's blocks where the
    # section stands, column by column). "A page's first list block" is the
    # first of these, so a block dragged above an older one is the first.
    # The sections are loaded with them, for their place alone: ONE
    # statement, and the order is worked out here. A block the outline does
    # not reach (its section's type holds no blocks any more, so the section
    # is not among the rows) comes last, by id: no line is lost to an order.
    def self.blocks(page_ids)
      rows = ContentBlock.where(owner_type: "Page", owner_id: page_ids).merge(ContentBlock.listing.or(ContentBlock.containers))
                         .select(:id, :owner_id, :owner_type, :block_type, :settings, :translated_settings, :position, :section_id, :section_column)
                         .order(:owner_id, :id).to_a
      rows.group_by(&:owner_id).flat_map do |_page_id, blocks|
        read = BlockOutline.new(blocks).reading_order
        (read + (blocks - read)).select { |block| block.definition&.capability?(:lists_posts) }
      end
    end

    def self.key(settings) = [ settings.content_type.presence&.to_s, settings.tag.to_s.strip.downcase.presence ]

    # `post_rows`: `[[id, content_type, recency, updated_at], …]`, as
    # `Site.rows_of` answers them (recency a number: the newest is the
    # highest); `tag_links`: `[[tag_id, post_id], …]`.
    def initialize(page_ids:, post_rows:, tag_links:)
      @post_rows = post_rows
      tags_of = {}
      tag_links.each { |tag_id, post_id| (tags_of[post_id] ||= []) << tag_id }
      @settings = {}
      self.class.blocks(page_ids).each do |block|
        settings = block.settings_object or next
        (@settings[block.owner_id] ||= []) << settings
      end
      names = @settings.values.flatten.filter_map { |settings| self.class.key(settings).last }.uniq
      named = Tag.named_any(names).order(:id).pluck(:id, :name)
      # A tag's id => its name as the criteria compare it, for the tags a
      # block names and no other; a name => the tag its line goes to.
      @tag_name = named.to_h { |id, name| [ id, name.downcase ] }
      @tag_label = named.to_h
      @tag_id = named.reverse.to_h { |id, name| [ name.downcase, id ] }
      # Newest first, once: by recency, then the higher id. `@rank` is a
      # post's place in that order, for a list put together from several.
      newest = post_rows.sort_by { |id, _type, recency, _stamp| [ -recency, -id ] }
      @rank = newest.each_with_index.to_h { |row, index| [ row.first, index ] }
      # A post's KIND: its stored type and the names of the tags it carries
      # that some block names (no other tag can decide anything), which is
      # all the criteria read. `@ordered` is `[[id, kind's index], …]`.
      kinds = {}
      @ordered = newest.map do |id, content_type, *|
        names = tags_of.fetch(id, []).filter_map { |tag_id| @tag_name[tag_id] }.sort
        [ id, kinds[[ content_type, names ]] ||= kinds.size ]
      end
      @kinds = kinds.keys
    end

    def edges
      @edges ||= @settings.flat_map { |page_id, all| all.filter_map { |settings| target(settings) }.uniq.map { |target| [ page_id, target ] } }
    end

    def targets(page_id) = (@targets ||= edges.group_by(&:first).transform_values { |rows| rows.map(&:last) }).fetch(page_id, [])
    def pages_of(target) = (@pages_of ||= edges.group_by(&:last).transform_values { |rows| rows.map(&:first) }).fetch(target, [])

    def tag_ids
      @tag_ids ||= @settings.values.flatten.filter_map { |settings| @tag_id[self.class.key(settings).last] }.to_set
    end

    # The posts a page's blocks list, newest first, each once. FROZEN: pages
    # whose blocks say the same are handed the same list.
    def posts_of(page_id)
      (@posts_of ||= {})[page_id] ||= listed_by(@settings.fetch(page_id, []).uniq { |settings| self.class.key(settings) })
    end

    def target_of(page_id, post_id)
      @settings.fetch(page_id, []).each do |settings|
        found = target(settings) or next
        return found if matched?(settings, post_id)
      end
      nil
    end

    def listed_count(page_id) = posts_of(page_id).size
    def listed?(post_id) = listed.include?(post_id)
    def unlisted = @ordered.filter_map { |id, _kind| id unless listed?(id) }

    # What each target of the page brings in beyond the `shown` newest posts
    # the local view draws (design answer H1: one "+N more" pill per target,
    # each counting only its own): `{ target => count }`.
    def left_out(page_id, shown: LISTED_IN_VIEW)
      posts_of(page_id).drop(shown).group_by { |post_id| target_of(page_id, post_id) }.transform_values(&:size)
    end

    def left_out_of(page_id, target, shown: LISTED_IN_VIEW)
      posts_of(page_id).drop(shown).select { |post_id| target_of(page_id, post_id) == target }
    end

    # The filter of the page's first list block, or of the first that points
    # at `target`: what "Open in Posts" filters the Posts screen by. The tag
    # is named AS ITS ROW NAMES IT, not as the block spells it: a block finds
    # its tag whatever the case, and the Posts screen's filter does not, so
    # a block that says "News" for the tag "news" would open an empty list.
    # (A name no tag has stays as the block has it: it lists nothing here
    # and there.)
    def filter_of(page_id, target = nil)
      all = @settings.fetch(page_id, [])
      settings = (target ? all.find { |candidate| target(candidate) == target } : all.first) or return {}
      name = settings.tag.to_s.strip.presence
      { type: settings.content_type.presence&.to_s, tag: name && @tag_label.fetch(@tag_id[name.downcase], name) }
    end

    def type_count(name) = (@type_counts ||= @post_rows.map { |_id, type, *| type }.tally).fetch(name.to_s, 0)
    # What "All posts" says beside its name (design answer H2: "the site
    # total"): EVERY post the viewer reads, one of a type that is no longer
    # registered included. Not what a block with no filter lists (it lists
    # no post of a retired type, `posts_of`): the number is the site's, as a
    # type hub's is the type's, and neither is a pill's arithmetic.
    def post_count = @post_rows.size

    private

    def target(settings)
      type, tag = self.class.key(settings)
      if tag then (id = @tag_id[tag]) && PostGraph.node_id(:tag, id)
      elsif type then PostGraph.node_id(:type, type)
      else ALL_POSTS
      end
    end

    # Every post some page lists: the union over the DISTINCT filters, not
    # over the pages (200 pages listing everything are one filter).
    def listed
      @listed ||= @settings.values.flatten.uniq { |settings| self.class.key(settings) }.each_with_object(Set.new) { |settings, all| all.merge(matching(settings)) }
    end

    # One list for every page whose blocks hold these filters, in whatever
    # order: a single filter's posts are in order as they come, several
    # filters' are put together by their place in the one order.
    def listed_by(all)
      keys = all.map { |settings| self.class.key(settings) }.sort_by(&:to_s)
      (@listed_by ||= {})[keys] ||= (all.one? ? matching(all.first) : all.flat_map { |settings| matching(settings) }.uniq.sort_by { |id| @rank.fetch(id) }).freeze
    end

    # The posts one filter lists, newest first. The criteria are the
    # listing's own, asked once per kind of post (see the header).
    def matching(settings)
      (@matching ||= {})[self.class.key(settings)] ||= begin
        listed = @kinds.map { |content_type, names| BlockTypes::PostList.matches?(settings, content_type: content_type, tag_names: names) }
        @ordered.filter_map { |id, kind| id if listed[kind] }.freeze
      end
    end

    # Asked once per post of a page (`left_out`), so by a set.
    def matched?(settings, post_id)
      ((@matched ||= {})[self.class.key(settings)] ||= matching(settings).to_set).include?(post_id)
    end
  end
end
