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

    # An action with a `dialog:` opens that dialog (the New page / New post
    # dialogs) instead of navigating: its row is still a link, to `path`, which
    # is what a viewer without JavaScript (or a dialog that isn't on the page)
    # gets. See `admin/jump/show`.
    ACTIONS = [
      { title: "New page", path: :new_admin_page_path, permission: "pages.create", dialog: "new-page-dialog" },
      { title: "New post", path: :new_admin_post_path, permission: "posts.create", dialog: "new-post-dialog" },
      { title: "Upload image", path: :admin_media_path, permission: "media.upload" },
      { title: "Change password", path: :admin_account_password_path, permission: nil }
    ].freeze

    # The Settings group (spec §7, round 1 second review): destinations
    # *inside* the Settings screen, shown as "Settings › X". `anchor` is the
    # id of the section on `admin_settings_path` (`site`, `languages`, `publishing`, `ai`; see
    # `Admin::SettingsScreen::NavComponent`). Each needs the right that owns its card on that one screen,
    # so a viewer is never offered a link that would 403. Sections (CS Studio's
    # modules) used to share this group's label -- "Settings" listing
    # Dashboard and Pages -- and are a group of their own now.
    SETTINGS_DESTINATIONS = [
      { title: "Settings › Site", path: :admin_settings_path, anchor: "site", permission: "settings.manage" },
      { title: "Settings › Publishing", path: :admin_settings_path, anchor: "publishing", permission: "settings.manage" },
      { title: "Settings › Languages", path: :admin_settings_path, anchor: "languages", permission: "languages.manage" },
      { title: "Settings › AI translation", path: :admin_settings_path, anchor: "ai", permission: "settings.manage" }
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
        group("Sections", module_rows), group("Settings", settings_rows), group("Actions", action_rows)
      ].compact
    end

    private

    attr_reader :actor, :query, :modules, :url_options

    def group(label, rows) = rows.empty? ? nil : { label: label, rows: rows.first(LIMIT) }
    def blank? = query.empty?
    def pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    def routes = Rails.application.routes.url_helpers
    def matches?(text) = text.to_s.downcase.include?(query.downcase)

    # `title` is a jsonb of { locale => text }. `jsonb_each_text` unnests it
    # so ILIKE tests only the VALUES: `title::text ILIKE` would also match a
    # locale key ("de", "en") or JSON punctuation, filling the LIMIT with
    # non-matches, and would miss a title containing `"` or `\` (jsonb's
    # text form escapes both).
    def titled(relation)
      relation.where("EXISTS (SELECT 1 FROM jsonb_each_text(#{relation.table_name}.title) AS t(locale, value) WHERE t.value ILIKE ?)", pattern)
        .order(updated_at: :desc).limit(LIMIT).to_a
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
        { title: asset.title.presence || "(untitled)", url: routes.admin_media_path(selected: asset.id, **url_options) }
      end
    end

    def module_rows
      modules.select { |entry| blank? || matches?(entry[:label]) }.map do |entry|
        { title: entry[:label], url: routes.public_send(entry[:path], **url_options) }
      end
    end

    def settings_rows
      SETTINGS_DESTINATIONS.select { |dest| AccessControl.holds?(actor, dest[:permission], channel: :admin) }
        .select { |dest| blank? || matches?(dest[:title]) }
        .map { |dest| { title: dest[:title], url: routes.public_send(dest[:path], **url_options, anchor: dest[:anchor]) } }
    end

    def action_rows
      ACTIONS.select { |action| action[:permission].nil? || AccessControl.holds?(actor, action[:permission], channel: :admin) }
        .select { |action| blank? || matches?(action[:title]) }
        .map { |action| { title: action[:title], url: routes.public_send(action[:path], **url_options), dialog: action[:dialog] }.compact }
    end

    def display_title(record) = Locales.read(record, :title, locale: Locales.default).presence || "(untitled)"
  end
end
