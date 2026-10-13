# The mind graph's search field (mind graph canvas spec §3.5; pages in the
# mind graph, spec §5): readable PAGES by title, readable posts by title
# (each in any language) and tags by name, up to `limit` of each, in that
# order. It is how a post the capped global view doesn't draw is reached.
#
# - PAGES come in TREE ORDER (`Tree#rank`: a tree is read by its order, not
#   by a score), the first `limit` of it, each with its address in `locale`
#   (else the default language's; nil when it has none): two pages may share
#   a title, and the path tells them apart. A page is loaded with its id and
#   its title only.
# - A post is loaded with its id, title and type only, never its body, and
#   carries its type's `colour_index` (nil for a type that is no longer
#   registered) for the row's dot: no colour here, as everywhere in the
#   graph's data.
# - A TAG is listed when a readable post carries it OR a readable page's
#   list block names it: the two ways `Focus` finds a tag, so a result never
#   leads to a 404, and never names a tag the viewer can't see used. (A tag
#   a page lists is a node of the graph whatever carries it, pages spec §1;
#   the block finds it by name whatever the case, as the listing does.)
#
# Everything through the read scope, which leaves the trash out. Six
# statements whatever the size: the readable pages' place in the tree, the
# matching pages, their addresses, the matching posts, the readable pages'
# list blocks, the tags.
module PostGraph
  class Search
    def self.call(...) = new(...).call

    def initialize(actor:, text:, locale: Locales.default, limit: 10)
      @actor = actor
      @text = text.to_s.strip
      @locale = locale
      @limit = limit
    end

    def call
      return [] if @text.empty?

      readable_pages = AccessControl.scope(@actor, "pages.read", Page.all)
      tree = Tree.new(readable_pages.pluck(:id, :parent_id, :position))
      pages = readable_pages.title_matching_any_locale(@text).select(:id, :title).select { |page| tree.ranked?(page.id) }.sort_by { |page| tree.rank(page.id) }.first(@limit)
      paths = PostGraph.paths(pages.map(&:id), locale: @locale)

      readable = AccessControl.scope(@actor, "posts.read", Post.all)
      posts = readable.title_matching_any_locale(@text).select(:id, :title, :content_type).order(:id).limit(@limit)
      carried = Tag.where(id: PostTag.where(post_id: readable.select(:id)).select(:tag_id))
      listed = Tag.named_any(Listings.blocks(readable_pages.select(:id)).filter_map { |block| block.settings_object&.tag.to_s.strip.presence }.uniq)
      tags = Tag.name_containing(@text).merge(carried.or(listed)).name_starting_first(@text).by_name.limit(@limit).pluck(:id, :name)

      pages.map { |page| { kind: "page", id: PostGraph.node_id(:page, page.id), record_id: page.id, label: Locales.read(page, :title, locale: @locale), path: paths[page.id] } } +
        posts.map { |post| { kind: "post", id: PostGraph.node_id(:post, post.id), record_id: post.id, label: Locales.read(post, :title, locale: @locale), colour_index: post.definition&.colour_index } } +
        tags.map { |id, name| { kind: "tag", id: PostGraph.node_id(:tag, id), record_id: id, label: name } }
    end
  end
end
