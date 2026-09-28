module Admin
  # The Posts module (cs-studio spec §4.1/§5.2): a filterable list, "New
  # post" (content type first, then everything else, like the page tree's
  # own title-only "Add a page"), and the post editor -- the page editor's
  # own shell/autosave/publish shape (`Admin::PagesController`), just folded
  # into one component (`Admin::PostFormComponent`) instead of a header plus
  # a settings form, since there's exactly one post form per screen (no
  # `Admin::BlockCardComponent`-style multi-instance-per-page id collision
  # to disambiguate against either).
  class PostsController < BaseController
    include AutosaveResponses
    include RichTextParams

    # `Posts::Save`'s own translated-column list, not a second hand-kept
    # copy -- same reasoning `Admin::ContentBlocksController::TRANSLATED_
    # COLUMNS` already gives for its own settings columns.
    TRANSLATED_COLUMNS = Posts::Save::TRANSLATED.map(&:to_s).freeze

    before_action :set_post, only: %i[show update destroy publish unpublish schedule]

    # Filters as query params (spec §5.2's "filters: content type, status,
    # tag, title search"): `type` is the bare registered name, `status` is
    # one of `Publishable::STATUSES`, `tag` is a tag's own name, `q` is a
    # title substring matched in the *editing* locale (not every locale --
    # an editor filtering the list they're currently reading in one
    # language expects that language's titles to match, not some other
    # one's). `title ->> locale` reads the jsonb column's own per-locale
    # text value directly (`posts.title` is a plain jsonb hash, `{locale =>
    # title}`) -- `where(title: ...)` on a jsonb column is the exact bug the
    # project's own Mobility convention warns against (CLAUDE.md), so this
    # goes around Mobility/ActiveRecord entirely for the ILIKE match one
    # locale's value needs.
    def index
      @content_types = ContentTypes.all
      @tags = Tag.order(:name)
      @posts = filtered_posts.includes(:tags).order(updated_at: :desc)
    end

    # "New post" (spec §5.2): asks for the content type up front, in the
    # same form as the title -- unlike a page's own title-only "Add a page",
    # a post has no tree position to default; its content type is fixed for
    # good the moment `create` below saves it (`Post#definition` never
    # changes after that), so there is no second chance to pick one later
    # the way a page's type-ish choices (page_type) stay editable in its own
    # settings form.
    def new
      @post = Post.new
      @content_types = ContentTypes.all
    end

    def create
      result = Posts::Save.call(Post.new, attributes: { content_type: params.dig(:post, :content_type), published: false },
        translations: { admin_locale => { title: params.dig(:post, :title) } })

      if result.ok?
        redirect_to admin_post_path(result.record, **admin_url_options), status: :see_other
      else
        @post = result.record
        @content_types = ContentTypes.all
        render :new, status: :unprocessable_entity
      end
    end

    def show
    end

    # The post form's own autosave endpoint (spec §6.1), same shape as
    # `Admin::PagesController#update`/`Admin::ContentBlocksController#update`:
    # `title`/`slug`/`excerpt`/`body` are translated columns, split into
    # `attributes:`/`translations:` the same fixed way every PATCH here does
    # (`body` is the rich-text document JSON, or the interim Markdown
    # textarea's `body_markdown` converted by `Admin::RichTextParams`); the content type's own typed `fields` are split *per field*
    # (`split_fields`, mirroring `Admin::ContentBlocksController
    # #split_settings`) since which of them are translated depends on the
    # registered type, not a fixed allowlist; `tag_names` arrives as one
    # comma-separated string (spec §5.2's own tag input) and is split into
    # the Array `Posts::Save` expects here, not in the service -- the
    # service is also used by MCP/seeds, which already hand it a real Array.
    #
    # `content_type` is never accepted here at all (not even silently
    # ignored -- it simply isn't in `TRANSLATED_COLUMNS` nor built into
    # `attributes`): the content type is fixed after creation (spec §5.2),
    # so there is no field in this form that could change it. `published`/
    # `published_at` are likewise absent -- those are the record header's
    # own one-shot `publish`/`unpublish`/`schedule` actions below, not
    # something a debounced autosave should ever be able to trigger.
    def update
      post_params = params.fetch(:post, ActionController::Parameters.new)
      translated = post_params.permit(*TRANSLATED_COLUMNS).to_h
      attributes = {}
      fields_hash = nil
      definition = @post.definition

      if definition && (post_params.key?(:fields) || post_params[:groups_present].present?)
        fields_hash = post_params.key?(:fields) ? post_params[:fields].to_unsafe_h : {}
        apply_missing_groups(fields_hash, definition, post_params[:groups_present])
        normalize_group_fields(fields_hash, definition)
        plain, translated_fields = split_fields(fields_hash, definition)
        attributes[:fields] = plain
        translated[:fields] = translated_fields
      end

      attributes[:tag_names] = split_tag_names(post_params[:tag_names]) if post_params.key?(:tag_names)
      body_warnings = apply_body_markdown(translated, post_params, @post)

      result = Posts::Save.call(@post, attributes: attributes, translations: { admin_locale => translated })

      streams = autosave_stream(
        record: result.record,
        result: result,
        status_id: "post-save-status",
        error_prefix: "post",
        base_updated_at: params[:base_updated_at],
        fields: post_error_fields
      )

      streams.concat(group_error_streams(result.record, definition, fields_hash)) if definition && fields_hash
      streams << body_warnings_stream("#{Admin::PostFormComponent::ID_PREFIX}-body", body_warnings) if body_warnings

      render turbo_stream: streams, status: (result.ok? ? :ok : :unprocessable_entity)
    end

    def destroy
      result = Posts::Destroy.call(@post)

      if result.ok?
        redirect_to admin_posts_path(**admin_url_options), status: :see_other
      else
        redirect_to admin_post_path(@post, **admin_url_options), status: :see_other, alert: result.errors.to_sentence
      end
    end

    def publish
      redirect_after Posts::Save.call(@post, attributes: { published: true }), success: "Published"
    end

    def unpublish
      redirect_after Posts::Save.call(@post, attributes: { published: false }), success: "Unpublished"
    end

    def schedule
      at = Time.zone.parse(params[:published_at].to_s)

      if at.nil?
        redirect_to admin_post_path(@post, **admin_url_options), status: :see_other, alert: "Choose a date and time"
        return
      end

      redirect_after Posts::Save.call(@post, attributes: { published_at: at }), success: "Scheduled"
    rescue ArgumentError
      redirect_to admin_post_path(@post, **admin_url_options), status: :see_other, alert: "Choose a date and time"
    end

    private

    def set_post
      @post = Post.find(params[:id])
    end

    def filtered_posts
      scope = Post.all
      scope = scope.where(content_type: params[:type]) if params[:type].present?
      scope = filter_by_status(scope, params[:status]) if params[:status].present?
      # A subquery, not `scope.joins(:tags).where(tags: { name: ... })`
      # directly (final-fixes round, finding 6): `index`'s own `.includes
      # (:tags)` right after this, combined with a `where` that references
      # the same `tags` table, is exactly what makes Rails silently upgrade
      # that `includes` into an `eager_load` (a single LEFT OUTER JOIN) --
      # and once the *listing* query's own join is filtered down to just the
      # matching tag, that's also all `post.tags` sees for the rest of that
      # row, not every tag the post actually has. Filtering by a subquery's
      # `id`s instead leaves the outer scope with no `tags` reference of its
      # own, so `includes` stays a real `includes` (a separate query,
      # preloading every tag) no matter which tag this list was filtered by.
      scope = scope.where(id: Post.joins(:tags).where(tags: { name: params[:tag] }).select(:id)) if params[:tag].present?
      scope = filter_by_title(scope, params[:q]) if params[:q].present?
      scope
    end

    def filter_by_status(scope, status)
      case status
      when "live" then scope.published
      when "scheduled" then scope.where("published_at > ?", Time.current)
      when "draft" then scope.where(published_at: nil)
      else scope
      end
    end

    def filter_by_title(scope, q)
      scope.where("posts.title ->> ? ILIKE ?", admin_locale, "%#{Post.sanitize_sql_like(q)}%")
    end

    # `Posts::Save` expects an Array of names (its own `assign_tags` calls
    # `Array(...)` on whatever it's handed, which would treat one
    # comma-separated string as a single, comma-laden tag name rather than
    # several) -- the comma-separated input is this controller's own UI
    # concern (spec §5.2), so the split happens here, once, rather than
    # teaching the service two different shapes for the same attribute.
    # Blanks are dropped here too (fix round 1 review) rather than left for
    # `Posts::Save#assign_tags`'s own `compact_blank`: a stray double comma
    # or trailing comma while typing (e.g. "a, , b") is exactly the kind of
    # input a comma-separated field invites, and this is the one place that
    # already knows the raw string is comma-separated at all -- `assign_tags`
    # only ever sees a plain Array by the time it runs.
    def split_tag_names(raw)
      raw.to_s.split(",").map(&:strip).reject(&:blank?)
    end

    # A `groups` field's raw params need straightening into an ordered Array
    # before `Post#assign_fields` -> `ContentModel::FieldSet#assign` ever
    # sees them -- see `Admin::FieldParams`'s own comment. Mirrors `Admin::
    # ContentBlocksController#normalize_group_fields` exactly; duplicated
    # rather than shared, since the two controllers' surrounding param
    # shapes (`block[settings]` vs `post[fields]`) already differ enough
    # that a shared helper would need its own indirection to call either.
    def normalize_group_fields(hash, definition)
      definition.fields.select { |field| field.type == :groups }.each do |field|
        key = field.name
        hash[key] = Admin::FieldParams.normalize(hash[key]) if hash.key?(key)
      end
    end

    # A `groups` field with every row removed sends no key of its own at all
    # (finding 2, final-fixes round) -- see `Admin::ContentBlocksController
    # #apply_missing_groups`'s own comment, which this mirrors exactly for a
    # post's typed `fields` instead of a block's `settings`.
    def apply_missing_groups(hash, definition, groups_present)
      present = Array(groups_present).map(&:to_s)

      definition.fields.select { |field| field.type == :groups && present.include?(field.name) }.each do |field|
        hash[field.name] = [] unless hash.key?(field.name)
      end
    end

    # Splits the submitted `fields` hash by `field.translated?`, the same
    # rule `Admin::ContentBlocksController#split_settings` applies to a
    # block's own schema fields -- untranslated keys go to `attributes[:fields]`
    # (assigned once, at `Locales.default`, inside `Posts::Save`), translated
    # ones to this locale's own `translations[locale][:fields]`.
    def split_fields(hash, definition)
      plain, translated = {}, {}

      definition.fields.each do |field|
        next unless hash.key?(field.name)

        (field.translated? ? translated : plain)[field.name] = hash[field.name]
      end

      [ plain, translated ]
    end

    # `fields:` for `Admin::AutosaveResponses#autosave_stream` -- every
    # column field reports directly under its own bare name (same as
    # `Admin::PagesController`'s own column fields, `slug`'s own locale-
    # suffixed accessor included, for the same reason that controller's own
    # comment gives); every typed schema field -- scalar, `group` or
    # `groups` alike -- reports under `"fields.#{field.name}"`, the exact
    # attribute `Post#fields_are_valid` reports a whole-field error against
    # (a scalar's own cast/inclusion failure, or a `group`/`groups` field's
    # own required/shape failure -- a *row's* own nested error, e.g.
    # "fields.speakers.0.name", is a different, dynamically-sized set of
    # slots `group_error_streams` below handles instead, since the row count
    # isn't known ahead of time the way this fixed field list is).
    #
    # Every `Admin::FieldComponent` this controller's own view renders for a
    # typed field is given `id_prefix: "post"` explicitly (`Admin::
    # PostFormComponent::ID_PREFIX`) rather than the default derived from
    # `form_name` ("post[fields]" -> "post_fields") -- so its errors_id
    # agrees with `Admin::FieldComponent.error_id("post", field.name)` here,
    # the same bare-"post" prefix every column field's own id already uses.
    def post_error_fields
      fields = {
        title: [ "title" ],
        slug: [ Mobility.normalize_locale_accessor(:slug, admin_locale) ],
        excerpt: [ "excerpt" ],
        body: [ "body" ],
        # No validation reports against `:tag_names` today (`Posts::Save
        # #assign_tags` finds-or-builds a `Tag` per name, and a blank/
        # duplicate name is already filtered out before it ever reaches
        # that point) -- wired up anyway so `Admin::TagInputComponent`'s own
        # error slot (fix round 1 review) is always cleared/replaced like
        # every other field's, and a later validation on this attribute
        # (e.g. rejecting a tag name that's too long) has somewhere to land
        # without a second wiring pass.
        tag_names: [ "tag_names" ]
      }

      @post.definition&.fields&.each { |field| fields[field.name] = [ "fields.#{field.name}" ] }
      fields
    end

    # Per-row/per-subfield error slots for a `group`/`groups` typed field
    # (cs-studio Task 7, carried in from Task 2's review) -- a dynamically
    # sized set `Admin::AutosaveResponses#autosave_stream`'s own fixed
    # `fields:` map has no way to express, since how many rows exist is only
    # known from *this* request's own submitted `fields_hash` (already
    # normalized into an ordered Array by `normalize_group_fields` above),
    # never from a static per-definition list the way `post_error_fields`'s
    # scalar/whole-field entries are. Every row is replaced whether it
    # currently has an error or not -- same "always replace, even with zero
    # messages" rule `autosave_stream` itself follows -- so a row whose
    # invalid subfield just got fixed has its stale message cleared too, not
    # just a newly-invalid one populated.
    #
    # `row_form_name`/`id_prefix` are reconstructed by hand here rather than
    # asked of `Admin::Fields::GroupField`/`GroupsField` directly (there's no
    # instance of either in a controller) -- but by the *exact* formula those
    # components' own default `id_prefix` (no override passed at the render
    # site, unlike `Admin::BlockCardComponent`'s -- see `Admin::
    # PostFormComponent`'s own comment for why there's nothing to
    # disambiguate against here) already derives: `Admin::FieldComponent.
    # dom_id_prefix("post[fields][#{field.name}]" plus, for a `groups` row,
    # "[#{index}]")`. Keeping the two in sync is why both this method and
    # `Admin::PostFormComponent`'s own field loop are the only two places
    # that ever have to agree on that literal `"post[fields]"` string.
    def group_error_streams(record, definition, fields_hash)
      definition.fields.select(&:group?).flat_map do |field|
        group_definition = FieldGroups.fetch(field.options[:of])
        rows = field.type == :groups ? Array(fields_hash[field.name]) : [ fields_hash[field.name] ].compact

        rows.each_with_index.flat_map do |_row, index|
          row_form_name = field.type == :groups ? "post[fields][#{field.name}][#{index}]" : "post[fields][#{field.name}]"
          id_prefix = Admin::FieldComponent.dom_id_prefix(row_form_name)

          group_definition.fields.map do |subfield|
            attribute = field.type == :groups ? "fields.#{field.name}.#{index}.#{subfield.name}" : "fields.#{field.name}.#{subfield.name}"
            id = Admin::FieldComponent.error_id(id_prefix, subfield.name)
            messages = record.errors.full_messages_for(attribute)
            turbo_stream.replace(id, partial: "admin/shared/field_errors", locals: { id: id, messages: messages })
          end
        end
      end
    end

    def redirect_after(result, success:)
      if result.ok?
        redirect_to admin_post_path(@post, **admin_url_options), status: :see_other, notice: success
      else
        redirect_to admin_post_path(@post, **admin_url_options), status: :see_other, alert: result.errors.to_sentence
      end
    end
  end
end
