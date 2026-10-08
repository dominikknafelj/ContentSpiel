# What a local graph is drawn around (mind graph canvas spec §3.1): one post
# or one tag, resolved from the request's `post=` / `tag=` for THIS viewer.
#
# Not found, never forbidden: a post outside the viewer's scope, a trashed
# post and an id that names nothing all raise `ActiveRecord::RecordNotFound`,
# and so does a tag no readable post carries -- a focus on it would say the
# tag exists and is in use somewhere the viewer can't look.
class PostGraph
  class Focus
    attr_reader :kind, :id, :title

    def self.find(actor:, post: nil, tag: nil, locale: Locales.default)
      readable = AccessControl.scope(actor, "posts.read", Post.all)
      if post.present?
        record = readable.find_by(id: Integer(post, exception: false)) or raise ActiveRecord::RecordNotFound
        new("post", record.id, Locales.read(record, :title, locale: locale))
      elsif tag.present?
        record = Tag.find_by(id: Integer(tag, exception: false)) or raise ActiveRecord::RecordNotFound
        raise ActiveRecord::RecordNotFound unless PostTag.where(tag_id: record.id, post_id: readable.select(:id)).exists?

        new("tag", record.id, record.name)
      end
    end

    def initialize(kind, id, title)
      @kind = kind
      @id = id
      @title = title.to_s
    end

    # The id the node carries in the graph's data.
    def node_id = kind == "tag" ? "tag-#{id}" : id
  end
end
