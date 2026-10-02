module Admin
  # The Translations overview (translation helpers spec §4): for one target
  # language (`?locale=de`, the editing locale too, so the sidebar and every
  # link keep it), the readable pages, posts and images that are `:missing`
  # or `:outdated` there, grouped by type, each linking to its editor in
  # that language. `?type=page|post|media` narrows it to one type.
  #
  # Only `index` lives here for now; the AI suggestion endpoint (Task 8)
  # joins it as a separate action on its own route, so nothing here may
  # assume `index` is the only action (every filter is `only: :index`).
  #
  # What's listed is exactly what the actor may read: pages and posts
  # through `AccessControl.scope` (kept records only, so the trash never
  # shows up here), images -- which have no per-record read scope -- only
  # for a `media.upload` holder, the same gate the Media module opens on,
  # and only kept ones. A type the actor can't read at all isn't offered
  # as a filter either.
  #
  # Where a record stands is `Translations::Status`, which is computed per
  # record in Ruby (field digests, block roll-ups, schema fields) -- there
  # is no column to `WHERE` on. So the list is built by walking every
  # readable record in id-ordered batches, computing each batch's states in
  # one go (one blocks query per batch), and keeping the ones that aren't
  # complete -- lazily, stopping as soon as this page (plus the one extra
  # row that tells whether there's a next page, the Media module's
  # `limit(N+1)` shape) is filled. The first pages are therefore cheap; a
  # late page, or a language with few gaps, walks the whole content once
  # per request. That's acceptable at CMS scale (hundreds to a few
  # thousand records) and tracked in the roadmap: a stored per-locale
  # state, kept current by the save services, is the way out if it isn't.
  class TranslationsController < BaseController
    PER_PAGE = 50
    BATCH_SIZE = 200

    # In display order; `label` heads the group.
    TYPES = {
      "page" => { label: "Pages", permission: "pages.read" },
      "post" => { label: "Posts", permission: "posts.read" },
      "media" => { label: "Images", permission: "media.upload" }
    }.freeze

    # One row of the list.
    Item = Data.define(:type, :record, :state)

    before_action :require_read_access, only: :index
    before_action :require_target_locale, only: :index

    def index
      @locale = params[:locale].to_s
      @target_locales = Translations.target_locales
      @types = TYPES.keys.select { |type| can?(TYPES.dig(type, :permission)) }
      @type = params[:type].presence_in(@types)
      @offset = offset

      items = needing_work.drop(@offset).first(PER_PAGE + 1)
      @has_next = items.size > PER_PAGE
      @items = items.first(PER_PAGE)
    end

    private

    # Same keys as the sidebar entry (`MODULES`): either read right opens
    # the screen; the list itself is then narrowed per type.
    def require_read_access
      forbidden! unless holds_any?(%w[pages.read posts.read])
    end

    # Always a real target language in the URL: an unknown, disabled or
    # default code (or none) goes to the first target language, keeping
    # the type filter. With a single language enabled there's nothing to
    # translate into (the sidebar hides the entry then), so the dashboard.
    def require_target_locale
      targets = Translations.target_locales
      return redirect_to(admin_root_path, status: :see_other) if targets.empty?
      return if targets.include?(params[:locale].to_s)

      redirect_to admin_translations_path(locale: targets.first, type: params[:type].presence), status: :see_other
    end

    # A lazy enumerator of `Item`s, types in `TYPES` order, each by id.
    def needing_work
      types = @type ? [ @type ] : @types
      types.lazy.flat_map do |type|
        readable(type).find_in_batches(batch_size: BATCH_SIZE).lazy.flat_map do |batch|
          Translations::Status.for(batch, locales: [ @locale ]).filter_map do |record, states|
            state = states.fetch(@locale)
            Item.new(type:, record:, state:) unless state == :complete
          end
        end
      end
    end

    def readable(type)
      case type
      when "page" then admin_scope(Page.all)
      when "post" then admin_scope(Post.all)
      when "media" then Media::Asset.kept
      end
    end

    def offset
      raw = params[:offset].to_i
      raw.positive? ? raw : 0
    end
  end
end
