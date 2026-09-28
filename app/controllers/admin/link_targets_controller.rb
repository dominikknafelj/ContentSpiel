module Admin
  # The Tiptap editor's own internal-link picker (design spec §4.1/§4.2)
  # searches pages and posts by title, in one locale, and hands back just
  # enough to let the editor insert an `internalLink` mark
  # (`{type, id}`, `RichText::BuiltIns`) without a second round trip: the
  # title to show in the picker, and the public path to preview.
  #
  # Unpublished pages/posts are included on purpose (the plan's own ruling):
  # an editor routinely links to something before publishing it, and the
  # public HTML renderer already degrades a non-visible target's link to
  # plain text (`RichText::BuiltIns#render_internal_link`) rather than ever
  # exposing it, so there's no leak in offering it here too.
  class LinkTargetsController < BaseController
    LIMIT = 20
    TYPES = %w[page post].freeze

    def index
      return render(json: { errors: [ "type must be page or post" ] }, status: :unprocessable_entity) unless requested_type.nil? || TYPES.include?(requested_type)

      results = []
      results.concat(page_results) if requested_type.nil? || requested_type == "page"
      results.concat(post_results) if requested_type.nil? || requested_type == "post"

      render json: results.first(LIMIT)
    end

    private

    def requested_type
      params[:type].presence
    end

    def query = params[:q].to_s

    def locale
      params[:locale].presence || admin_locale
    end

    # `title ->> locale` read as raw SQL, not Mobility's own `.i18n` scope
    # or a plain `where(title: ...)` -- `Page#title`/`Post#title` are jsonb
    # columns (`{ locale => title }`), so comparing one to a bare String
    # with `where` would compare jsonb to text and never match a row (the
    # exact bug CLAUDE.md's own Mobility note warns about); this is the
    # same `->> ? ILIKE ?` shape `Admin::PostsController#filter_by_title`
    # already uses for its own title search, applied here to both models.
    # `sanitize_sql_like` is what keeps a literal `%`/`_` in the query from
    # being read as a SQL wildcard instead of a character to match.
    def page_results
      scope = Page.all
      scope = scope.where("pages.title ->> ? ILIKE ?", locale, "%#{Page.sanitize_sql_like(query)}%") if query.present?
      scope.order(:id).limit(LIMIT).map { |page| target_json("page", page) }
    end

    def post_results
      scope = Post.all
      scope = scope.where("posts.title ->> ? ILIKE ?", locale, "%#{Post.sanitize_sql_like(query)}%") if query.present?
      scope.order(:id).limit(LIMIT).map { |post| target_json("post", post) }
    end

    # `title` is read through Mobility (`public_send`'s own per-locale
    # accessor), not the raw `->>` value the query above matched against --
    # falls back to `:en` the same way every other translated read in this
    # app does, rather than a blank title, when `locale` itself has no
    # translation for this record.
    #
    # `path` is the plain public path (`PublicSite::Urls.new`, no
    # `preview:`) -- admin-preview-agnostic, per the plan's own ruling: this
    # is a picker result, not a rendered link, so it has no reason to carry
    # `/preview`'s own prefix the way `RichText::BuiltIns#render_internal_
    # link` does when actually rendering inside a preview request. `nil`
    # when the record has no path at all in this locale (an unpublished
    # page with no canonical listing yet, e.g.) -- the editor still gets a
    # title and an id to link to, just nothing to preview yet.
    def target_json(type, record)
      { type: type, id: record.id, title: record.public_send(Mobility.normalize_locale_accessor(:title, locale)), path: PublicSite::Urls.new.path_for(record, locale) }
    end
  end
end
