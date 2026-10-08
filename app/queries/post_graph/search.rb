# The mind graph's search field (mind graph canvas spec §3.5): readable posts
# by title (in any language) and tags by name, up to `limit` of each. It is
# how a post the capped global view doesn't draw is reached. A tag is listed
# only when a readable post carries it, the same rule `Focus` applies -- so a
# result never leads to a 404, and never names a tag the viewer can't see used.
class PostGraph
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

      readable = AccessControl.scope(@actor, "posts.read", Post.all)
      posts = readable.title_matching_any_locale(@text).order(:id).limit(@limit)
      tags = Tag.name_containing(@text).where(id: PostTag.where(post_id: readable.select(:id)).select(:tag_id))
                .name_starting_first(@text).by_name.limit(@limit).pluck(:id, :name)

      posts.map { |post| { kind: "post", id: post.id, label: Locales.read(post, :title, locale: @locale) } } +
        tags.map { |id, name| { kind: "tag", id: id, label: name } }
    end
  end
end
