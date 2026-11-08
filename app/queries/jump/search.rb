module Jump
  # What ⌘K finds: titles only -- pages, posts and library images the viewer
  # may read, CS Studio's own modules, the Settings screen's sections and a
  # few actions. Full-text search is a separate roadmap item; this is a way to
  # *go* somewhere, not to find a phrase.
  #
  # Read-scoped the same way every list is (`AccessControl.scope`, which
  # also hides trashed records, `docs/reference/trash.md`; `Media::Asset.kept` does
  # the same for images, which have no read scope of their own), so a title
  # the viewer couldn't open is never suggested.
  #
  # The query is user text inside a LIKE pattern: the title scope
  # (`TitleSearch`) escapes `%`, `_` and `\` (`SqlNodes.like_pattern`), so "%"
  # searches for a percent sign rather than matching everything. It is cut to
  # MAX_QUERY characters first, so a pasted novel is a short search, not an
  # error.
  #
  # A row says where it goes as a ROUTE -- `[route name, arguments, params]`,
  # `[:admin_page_path, [ page ], {}]` -- and never as a URL: a query knows no
  # routes and none of the request's URL options (the editing locale), so the
  # one view (`admin/jump/show`, through `Admin::JumpHelper#jump_row_path`)
  # resolves it, against a fixed list of route names, with the options of its
  # own request. The same hand-over `Audit::Sentence::Route` makes. An
  # argument is a record or an id; a param is a query param or an `anchor`.
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
      { title: "Your account", path: :admin_account_path, permission: nil }
    ].freeze

    # The Settings group: the sections of the Settings screen
    # (`SettingsSections`), in its nav's order, each a link to its card's
    # heading (`anchor: "mail"`) under the right that owns the card, so a
    # viewer is never offered a link that would 403. The group is not cut to
    # LIMIT: a blank query lists every section the viewer may manage. The titles are what a
    # person types against, so they stay here, English, keyed by the
    # sections' ids.
    SETTINGS_TITLES = {
      "site" => "Settings › Site",
      "languages" => "Settings › Languages",
      "publishing" => "Settings › Publishing",
      "forms" => "Settings › Forms",
      "ai" => "Settings › AI translation",
      "mail" => "Settings › Mail",
      "images" => "Settings › Images"
    }.freeze

    def initialize(actor:, query:, modules:)
      @actor = actor
      @query = query.is_a?(String) ? query.strip.first(MAX_QUERY) : ""
      @modules = modules
    end

    def groups
      [
        group("Pages", page_rows), group("Posts", post_rows), group("Media", media_rows),
        group("Sections", module_rows), group("Settings", settings_rows, limit: nil), group("Actions", action_rows)
      ].compact
    end

    private

    attr_reader :actor, :query, :modules

    # `limit: nil` for a group whose rows are a short fixed list, every one of
    # which a blank query offers (the Settings sections).
    def group(label, rows, limit: LIMIT) = rows.empty? ? nil : { label: label, rows: limit ? rows.first(limit) : rows }
    def blank? = query.empty?
    def matches?(text) = text.to_s.downcase.include?(query.downcase)

    # Titles in EVERY language, values only (`TitleSearch
    # #title_matching_any_locale` says why not `title::text ILIKE`: it would
    # fill the LIMIT with matches on locale keys and JSON punctuation).
    def titled(relation)
      relation.title_matching_any_locale(query).order(updated_at: :desc).limit(LIMIT).to_a
    end

    def page_rows
      return [] if blank?
      titled(AccessControl.scope(actor, "pages.read", Page.all, channel: :admin)).map do |page|
        { title: display_title(page), route: [ :admin_page_path, [ page ], {} ], status: page.status }
      end
    end

    def post_rows
      return [] if blank?
      titled(AccessControl.scope(actor, "posts.read", Post.all, channel: :admin)).map do |post|
        { title: display_title(post), route: [ :admin_post_path, [ post ], {} ], status: post.status, hint: post.content_type }
      end
    end

    # The library is browsable with `media.upload` alone (no read scope), the
    # same gate as the Media module.
    def media_rows
      return [] if blank? || !AccessControl.holds?(actor, "media.upload", channel: :admin)
      Media::Search.call(Media::Asset.kept, query).order(id: :desc).limit(LIMIT).map do |asset|
        { title: asset.title.presence || "(untitled)", route: [ :admin_media_path, [], { selected: asset.id } ] }
      end
    end

    def module_rows
      modules.select { |entry| blank? || matches?(entry[:label]) }.map do |entry|
        { title: entry[:label], route: [ entry[:path], [], {} ] }
      end
    end

    def settings_rows
      SettingsSections.for { |permission| AccessControl.holds?(actor, permission, channel: :admin) }
        .map { |section| { title: SETTINGS_TITLES.fetch(section.id), route: [ :admin_settings_path, [], { anchor: section.id } ] } }
        .select { |row| blank? || matches?(row[:title]) }
    end

    def action_rows
      ACTIONS.select { |action| action[:permission].nil? || AccessControl.holds?(actor, action[:permission], channel: :admin) }
        .select { |action| blank? || matches?(action[:title]) }
        .map { |action| { title: action[:title], route: [ action[:path], [], {} ], dialog: action[:dialog] }.compact }
    end

    def display_title(record) = Locales.read(record, :title, locale: Locales.default).presence || "(untitled)"
  end
end
