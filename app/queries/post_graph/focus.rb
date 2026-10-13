# What a local graph is drawn around (mind graph canvas spec §3.1; pages in
# the mind graph, spec §7): one page, one post or one tag, resolved from the
# request's `page=` / `post=` / `tag=` for THIS viewer. Page wins over post,
# and post over tag.
#
# Not found, never forbidden: a page or a post outside the viewer's scope, a
# trashed one and an id that names nothing all raise
# `ActiveRecord::RecordNotFound`, and so does a tag that neither a readable
# post carries NOR a readable page lists -- a focus on it would say the tag
# exists and is in use somewhere the viewer can't look. (The second way in:
# a tag a readable page's list block names is a node of the graph whatever
# carries it, pages spec §1, so it is a focus too.) An id that is not a
# decimal number is one that names nothing.
module PostGraph
  class Focus
    attr_reader :kind, :id, :title

    def self.find(actor:, page: nil, post: nil, tag: nil, locale: Locales.default)
      readable = AccessControl.scope(actor, "posts.read", Post.all)
      if page.present?
        record = AccessControl.scope(actor, "pages.read", Page.all).find_by(id: id_from(page)) or raise ActiveRecord::RecordNotFound
        new("page", record.id, Locales.read(record, :title, locale: locale))
      elsif post.present?
        record = readable.find_by(id: id_from(post)) or raise ActiveRecord::RecordNotFound
        new("post", record.id, Locales.read(record, :title, locale: locale))
      elsif tag.present?
        record = Tag.find_by(id: id_from(tag)) or raise ActiveRecord::RecordNotFound
        raise ActiveRecord::RecordNotFound unless PostTag.where(tag_id: record.id, post_id: readable.select(:id)).exists? || listed?(record, actor)

        new("tag", record.id, record.name)
      end
    end

    # A tag is a node also when a page the viewer can read lists it (pages
    # spec §1): the viewer can read the page, and its block names the tag.
    # Asked only when no readable post carries it: one statement.
    def self.listed?(tag, actor)
      pages = AccessControl.scope(actor, "pages.read", Page.all).select(:id)
      Listings.blocks(pages).any? { |block| block.settings_object&.tag.to_s.strip.casecmp?(tag.name) }
    end
    private_class_method :listed?

    # An id as the URL writes it: decimal, whatever it begins with. Without the
    # base, Ruby reads a prefix -- `?post=010` would be post 8 and `0x1A` post
    # 26, each a post other than the one the URL names. Anything that is not a
    # decimal number (a word, a list from `post[]=1`) is nil, which finds
    # nothing.
    def self.id_from(value) = Integer(value.to_s, 10, exception: false)
    private_class_method :id_from

    def initialize(kind, id, title)
      @kind = kind
      @id = id
      @title = title.to_s
    end

    # The id the node carries in the graph's data.
    def node_id = PostGraph.node_id(kind, id)
  end
end
