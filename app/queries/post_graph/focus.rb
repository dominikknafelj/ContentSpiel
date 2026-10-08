# What a local graph is drawn around (mind graph canvas spec §3.1): one post
# or one tag, resolved from the request's `post=` / `tag=` for THIS viewer.
#
# Not found, never forbidden: a post outside the viewer's scope, a trashed
# post and an id that names nothing all raise `ActiveRecord::RecordNotFound`,
# and so does a tag no readable post carries -- a focus on it would say the
# tag exists and is in use somewhere the viewer can't look. An id that is not
# a decimal number is one that names nothing.
module PostGraph
  class Focus
    attr_reader :kind, :id, :title

    def self.find(actor:, post: nil, tag: nil, locale: Locales.default)
      readable = AccessControl.scope(actor, "posts.read", Post.all)
      if post.present?
        record = readable.find_by(id: id_from(post)) or raise ActiveRecord::RecordNotFound
        new("post", record.id, Locales.read(record, :title, locale: locale))
      elsif tag.present?
        record = Tag.find_by(id: id_from(tag)) or raise ActiveRecord::RecordNotFound
        raise ActiveRecord::RecordNotFound unless PostTag.where(tag_id: record.id, post_id: readable.select(:id)).exists?

        new("tag", record.id, record.name)
      end
    end

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
    def node_id = kind == "tag" ? "tag-#{id}" : id
  end
end
