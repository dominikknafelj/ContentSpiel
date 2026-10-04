module Jump
  # What ⌘K finds (design pass spec §5.6): titles only -- pages, posts and
  # library images the viewer may read, CS Studio's own modules, and a few
  # actions. Full-text search is a separate roadmap item; this is a way to
  # *go* somewhere, not to find a phrase.
  #
  # Read-scoped the same way every list is (`AccessControl.scope`, which
  # also hides trashed records -- trash spec §5.4; `Media::Asset.kept` does
  # the same for images, which have no read scope of their own), so a title
  # the viewer couldn't open is never suggested.
  #
  # The query is user text inside a LIKE pattern: `sanitize_sql_like`
  # escapes `%`, `_` and `\`, so "%" searches for a percent sign rather than
  # matching everything. It is cut to MAX_QUERY characters first, so a
  # pasted novel is a short search, not an error.
  class Search
    LIMIT = 5
    MAX_QUERY = 100

    ACTIONS = [
      { title: "New page", path: :new_admin_page_path, permission: "pages.create" },
      { title: "New post", path: :new_admin_post_path, permission: "posts.create" },
      { title: "Upload image", path: :admin_media_path, permission: "media.upload" },
      { title: "Change password", path: :admin_account_password_path, permission: nil }
    ].freeze

    def initialize(actor:, query:, modules:, url_options: {})
      @actor = actor
      @query = query.is_a?(String) ? query.strip.first(MAX_QUERY) : ""
      @modules = modules
      @url_options = url_options
    end

    def groups
      [
        group("Pages", page_rows), group("Posts", post_rows), group("Media", media_rows),
        group("Settings", module_rows), group("Actions", action_rows)
      ].compact
    end

    private

    attr_reader :actor, :query, :modules, :url_options

    def group(label, rows) = rows.empty? ? nil : { label: label, rows: rows.first(LIMIT) }
    def blank? = query.empty?
    def pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    def routes = Rails.application.routes.url_helpers
    def matches?(text) = text.to_s.downcase.include?(query.downcase)

    # `title` is a jsonb of { locale => text }: `title::text ILIKE` matches
    # any language's title in one predicate. It can also match a locale
    # *key* (or JSON punctuation) for a short query like "de"; the Ruby-side
    # filter drops those, and the over-fetch keeps the group full anyway.
    def titled(relation)
      relation.where("#{relation.table_name}.title::text ILIKE ?", pattern).order(updated_at: :desc).limit(LIMIT * 4)
        .select { |record| record.read_attribute(:title).to_h.values.any? { |value| matches?(value) } }
        .first(LIMIT)
    end

    def page_rows
      return [] if blank?
      titled(AccessControl.scope(actor, "pages.read", Page.all, channel: :admin)).map do |page|
        { title: display_title(page), url: routes.admin_page_path(page, **url_options), status: page.status }
      end
    end

    def post_rows
      return [] if blank?
      titled(AccessControl.scope(actor, "posts.read", Post.all, channel: :admin)).map do |post|
        { title: display_title(post), url: routes.admin_post_path(post, **url_options), status: post.status, hint: post.content_type }
      end
    end

    # The library is browsable with `media.upload` alone (no read scope), the
    # same gate as the Media module.
    def media_rows
      return [] if blank? || !AccessControl.holds?(actor, "media.upload", channel: :admin)
      Media::Search.call(Media::Asset.kept, query).order(id: :desc).limit(LIMIT).map do |asset|
        { title: asset.title.presence || "(untitled)", url: routes.admin_medium_path(asset, **url_options) }
      end
    end

    def module_rows
      modules.select { |entry| blank? || matches?(entry[:label]) }.map do |entry|
        { title: entry[:label], url: routes.public_send(entry[:path], **url_options) }
      end
    end

    def action_rows
      ACTIONS.select { |action| action[:permission].nil? || AccessControl.holds?(actor, action[:permission], channel: :admin) }
        .select { |action| blank? || matches?(action[:title]) }
        .map { |action| { title: action[:title], url: routes.public_send(action[:path], **url_options) } }
    end

    def display_title(record) = Locales.read(record, :title, locale: Locales.default).presence || "(untitled)"
  end
end
