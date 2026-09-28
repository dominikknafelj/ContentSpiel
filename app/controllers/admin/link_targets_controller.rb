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

      # Fix round 1's minor note: gathered as bare records first, capped at
      # `LIMIT` *before* any of the per-record work below runs (Mobility's
      # translated-title read, `path_for`'s own `PublicPath` lookup) --
      # `page_candidates`/`post_candidates` can hand back up to `LIMIT` each,
      # but only the first `LIMIT` combined are ever rendered, so this
      # never does that work for up to twice as many candidates as the
      # response could ever include.
      candidates = []
      candidates.concat(page_candidates) if requested_type.nil? || requested_type == "page"
      candidates.concat(post_candidates) if requested_type.nil? || requested_type == "post"

      # Fix round 1's I2: one `PublicSite::Urls` for the whole request, not
      # a fresh instance per result -- `Urls` memoizes `path_for` lookups
      # per instance (its own comment: "one instance per request renders
      # every ... link off it"), which a brand-new instance per record
      # throws away before it can ever help, and needlessly rebuilds
      # `PublicSite::Urls.default_host` (an `ENV.fetch`) on every result.
      urls = PublicSite::Urls.new
      render json: candidates.first(LIMIT).map { |type, record| target_json(type, record, urls) }
    end

    private

    def requested_type
      params[:type].presence
    end

    def query = params[:q].to_s

    # Fix round 1's I1: `params[:locale]` is free-form user input -- a
    # malformed value ("en US", say) isn't an *enabled* locale, so this
    # falls back exactly the way `Admin::BaseController#admin_locale`
    # itself does, rather than reaching `target_json`'s own `Mobility
    # .normalize_locale_accessor` call with something that isn't a valid
    # locale code at all and raising `ArgumentError` (a 500) instead of
    # just answering with the admin's own current editing language.
    def locale
      Locales.enabled?(params[:locale]) ? params[:locale].to_s : admin_locale
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
    #
    # Returns `[type, record]` pairs, not JSON -- `#index` above caps the
    # *combined* set at `LIMIT` before `target_json` ever runs on any of
    # these, so this is deliberately cheaper than a full result: an id
    # lookup and an ordering, nothing translated or path-resolved yet.
    def page_candidates
      scope = Page.all
      scope = scope.where("pages.title ->> ? ILIKE ?", locale, "%#{Page.sanitize_sql_like(query)}%") if query.present?
      scope.order(:id).limit(LIMIT).map { |page| [ "page", page ] }
    end

    def post_candidates
      scope = Post.all
      scope = scope.where("posts.title ->> ? ILIKE ?", locale, "%#{Post.sanitize_sql_like(query)}%") if query.present?
      scope.order(:id).limit(LIMIT).map { |post| [ "post", post ] }
    end

    # `title` is read through Mobility (`public_send`'s own per-locale
    # accessor), not the raw `->>` value the query above matched against --
    # falls back to `:en` the same way every other translated read in this
    # app does, rather than a blank title, when `locale` itself has no
    # translation for this record.
    #
    # `path` is the plain public path (`urls.path_for`, `urls` built with no
    # `preview:`) -- admin-preview-agnostic, per the plan's own ruling: this
    # is a picker result, not a rendered link, so it has no reason to carry
    # `/preview`'s own prefix the way `RichText::BuiltIns#render_internal_
    # link` does when actually rendering inside a preview request. `nil`
    # when the record has no path at all in this locale (an unpublished
    # page with no canonical listing yet, e.g.) -- the editor still gets a
    # title and an id to link to, just nothing to preview yet.
    def target_json(type, record, urls)
      { type: type, id: record.id, title: record.public_send(Mobility.normalize_locale_accessor(:title, locale)), path: urls.path_for(record, locale) }
    end
  end
end
