module Public
  # The bar a signed-in editor sees across the top of a preview (`/preview...`,
  # `PreviewController`; design pass round 3, handoff C40, plan D26):
  # "PREVIEW · <title> · <Draft|Scheduled|Live> · <the language's own name>",
  # then Edit and Exit preview. It is the public site's own chrome: it renders
  # in the public layout with the public theme's stylesheet only, never the
  # product one or any admin JavaScript, and its two colours are theme tokens
  # (`--th-preview-bg` / `--th-preview-ink`) that do not switch with light and
  # dark.
  #
  # `Public` is a new top-level namespace (nothing else defines it:
  # `PublicController` and `PublicSite` are different constants), holding the
  # public layout's own components as opposed to the block/post/field ones.
  #
  # Where its two links go:
  # - Edit: the record's CS Studio editor in the previewed language (`locale:`
  #   only when it isn't the default, like every admin link). A preview viewer
  #   can read the record by definition (`PreviewController#readable?`).
  # - Exit preview (plan D26, amended): the record's public URL in the previewed
  #   language when it is live, since that is then where a visitor would see
  #   it; otherwise there is no public page to leave for and Edit already is
  #   the editor, so it goes to CS Studio's list instead: the pages landing for
  #   a page, the posts list for a post (the language kept).
  #
  # The response is never cached (`Cache-Control: private, no-store`), and the
  # bar must not become part of any cached render: nothing here is memoised or
  # fragment-cached.
  class PreviewBarComponent < ApplicationComponent
    HEIGHT_CLASS = "h-9".freeze

    def initialize(record:, locale:)
      @record = record
      @locale = locale.to_s
    end

    private

    attr_reader :record, :locale

    def title = translated(record, :title).presence || "(untitled)"

    def status = record.status.humanize

    def language = Locales.name(locale, native: true)

    def editor_path
      options = locale == Locales.default ? {} : { locale: locale }
      record.is_a?(Post) ? helpers.admin_post_path(record, **options) : helpers.admin_page_path(record, **options)
    end

    def exit_path
      (record.live? && PublicSite::Urls.new.path_for(record, locale)) || studio_list_path
    end

    def studio_list_path
      options = locale == Locales.default ? {} : { locale: locale }
      record.is_a?(Post) ? helpers.admin_posts_path(**options) : helpers.admin_pages_path(**options)
    end
  end
end
