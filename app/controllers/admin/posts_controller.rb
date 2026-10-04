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
    include Scheduling
    include BulkResponses

    # `Posts::Save`'s own translated-column list, not a second hand-kept
    # copy -- same reasoning `Admin::ContentBlocksController::TRANSLATED_
    # COLUMNS` already gives for its own settings columns.
    TRANSLATED_COLUMNS = Posts::Save::TRANSLATED.map(&:to_s).freeze
    PER_PAGE = 50

    before_action :set_post, only: %i[show update destroy publish unpublish schedule]
    # The list (and the module itself) needs `posts.read` somewhere; the
    # rows are then narrowed to the readable ones (`filtered_posts`).
    # "New post" needs `posts.create` for at least one content type.
    before_action -> { require_permission("posts.read") }, only: %i[index bulk]
    before_action -> { require_permission("posts.create") }, only: %i[new create]

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
      @scope = list_scope
      @counts = scope_counts
      @pagination = Pagination.new(page: params[:page], per_page: PER_PAGE, total: @counts.fetch(@scope))
      # A page past the end shows the "back to page 1" notice and no rows:
      # don't query rows that were never going to be shown.
      @posts = @pagination.out_of_range? ? [] : page_of_posts
      @paths = listed_paths(@posts)
      # The "Languages" column (translation helpers spec §4): every listed
      # post's state per target language, worked out once for the whole
      # page, so the column costs the same queries however many rows it
      # shows. Read from the stored `translation_states` rows
      # (`Translations::StateIndex`), one query for the whole page.
      @translation_states = Translations::StateIndex.states_for(@posts)
    end

    # Publishes or moves to the trash the posts ticked on the list (Task 17).
    # All the rules live in `Posts::Bulk` (one single-record service per
    # post, so each post is authorised, audited and answered on its own);
    # this turns its `Result` into one toast and sends the editor back to
    # the list they were on, filters and page kept (`list_params`).
    def bulk
      action = params[:bulk_action].to_s
      return refuse_bulk("Unknown bulk action") unless Posts::Bulk::ACTIONS.include?(action)

      ids = bulk_ids
      return redirect_to(posts_list_path, alert: "Select at least one post.", status: :see_other) if ids.empty?

      begin
        result = Posts::Bulk.call(action:, ids:)
      rescue ArgumentError
        return refuse_bulk("Select at most #{Posts::Bulk::MAX_IDS} posts at a time")
      end

      trashing = action == "trash"
      # One Undo for the whole batch, restoring exactly the posts this action
      # moved (`done`, never "whatever is in the trash"): a route of its own,
      # which carries the ids and the list's filters.
      # The list's filters ride in `back`: they have their own `type`, which
      # must not collide with the Undo route's `type=post`.
      undo_url = admin_restore_many_trash_path(type: "post", ids: result.done.map(&:id), back: list_filters, **admin_url_options) if trashing && undo_offered?(result.done)
      flash_bulk_result(done: result.done, refused: result.refused, not_found: result.not_found,
        verb: trashing ? "Moved" : "Published", suffix: trashing ? " to the trash" : "", undo_url:)
      redirect_to posts_list_path, status: :see_other
    end

    # The no-JS fallback of the New post dialog (design pass round 2, Task 15):
    # the same form (`Admin::EditorScreen::NewPostFormComponent`) as a page of
    # its own; with JavaScript every "New post" trigger opens the dialog in
    # the layout instead. The content type is chosen here and nowhere else: it
    # is fixed for good the moment `create` below saves it (`Post#definition`
    # never changes after that), unlike a page's type, which stays editable.
    def new
      @post = Post.new(content_type: params[:type])
      # `posts.create` for at least one type (the `before_action`) is not yet a
      # type to offer: the form itself is the judge, as `pages#new` is. The one
      # instance is what the view renders (its listing-path queries run once).
      @form = Admin::EditorScreen::NewPostFormComponent.new(url_options: admin_url_options, locale: admin_locale,
        content_type: params[:type], title: params[:title])
      return forbidden! unless @form.creatable?

      render :new_frame, layout: false if turbo_frame_request_id == Admin::EditorScreen::NewPostDialogComponent::FRAME_ID
    end

    # From the dialog (type, title) or the standalone form: a draft of the
    # chosen type. A type the viewer may not create is a `denied` from
    # `Posts::Save` (one `access.denied` event, the 403 page) however the
    # request was forged; a blank title is a 422 that, for a Turbo submission,
    # replaces just the dialog's form (typed values kept, error summary on top)
    # and, without JS, re-renders the standalone page.
    def create
      result = Posts::Save.call(Post.new, attributes: { content_type: params.dig(:post, :content_type), published: false },
        translations: { admin_locale => { title: params.dig(:post, :title) } })

      if result.ok?
        redirect_to admin_post_path(result.record, **admin_url_options), status: :see_other
      else
        forbidden_or(result) do
          @post = result.record
          @post.errors.add(:base, result.errors.to_sentence) if @post.errors.empty?
          render_new_post_failure
        end
      end
    end

    def show
    end

    # The post form's own autosave endpoint (spec §6.1), same shape as
    # `Admin::PagesController#update`/`Admin::ContentBlocksController#update`:
    # `title`/`slug`/`excerpt`/`body` are translated columns, split into
    # `attributes:`/`translations:` the same fixed way every PATCH here does
    # (`body` is the rich-text document JSON the Tiptap editor writes into
    # its hidden input, `admin--rich-text`, passed through untouched --
    # `HasRichTextBody` parses and validates it); the content type's own
    # typed `fields` are split *per field*
    # (`split_fields`, mirroring `Admin::ContentBlocksController
    # #split_settings`) since which of them are translated depends on the
    # registered type, not a fixed allowlist; `tag_names` arrives as an Array
    # (the chip input's `tag_names[]`) or as one legacy comma-separated
    # string, split into the Array `Posts::Save` expects here, not in the service -- the
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
      return if refuse_stale_autosave(@post, status_id: "post-save-status", error_prefix: "post", reload_url: admin_post_path(@post, **admin_url_options))

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

      tag_names = split_tag_names(post_params[:tag_names]) if post_params.key?(:tag_names)
      attributes[:tag_names] = tag_names if tag_names

      # The related-posts picker's own contract (`Admin::RelatedPostsComponent`
      # / `Posts::Save#assign_related_posts`): passed on only when the key
      # was actually submitted -- absent leaves the relations alone, the
      # picker's blank sentinel alone (`[""]`) clears them.
      attributes[:related_post_ids] = Array(post_params.permit(related_post_ids: [])[:related_post_ids]) if post_params.key?(:related_post_ids)

      result = Posts::Save.call(@post, attributes: attributes, translations: { admin_locale => translated })

      streams = autosave_stream(
        record: result.record,
        result: result,
        status_id: "post-save-status",
        error_prefix: "post",
        fields: post_error_fields
      )

      streams.concat(group_error_streams(result.record, definition, fields_hash)) if definition && fields_hash

      render turbo_stream: streams, status: autosave_status(result)
    end

    # Moves the post to the trash (`Trash::Move`, trash spec §4.1); the
    # permanent delete is `Trash::Purge`, reachable only from the trash. The
    # Undo link's own URL carries `from: "undo"` (`Admin::TrashController
    # #restore`) so restoring lands the actor back on this post's editor,
    # not the Trash screen.
    def destroy
      result = Trash::Move.call(@post)

      if result.ok?
        flash[:undo] = { "label" => "Undo", "url" => admin_restore_trash_item_path("post", @post, from: "undo", **admin_url_options) }
        redirect_to admin_posts_path(**admin_url_options), notice: "Moved “#{@post.title}” to the trash", status: :see_other
      else
        forbidden_or(result) { redirect_to admin_post_path(@post, **admin_url_options), status: :see_other, alert: result.errors.to_sentence }
      end
    end

    def publish
      redirect_after Posts::Save.call(@post, attributes: { published: true }), success: "Published"
    end

    def unpublish
      redirect_after Posts::Save.call(@post, attributes: { published: false }), success: "Unpublished"
    end

    def schedule
      editor = admin_post_path(@post, **admin_url_options)

      if params[:remove] == "1"
        # "Remove schedule" is only offered for a scheduled record; for any
        # other it must not become an unpublish (a live record's
        # `published_at` is in the past), so it changes nothing.
        return redirect_to editor, status: :see_other unless @post.status == "scheduled"

        return redirect_after Posts::Save.call(@post, attributes: { published_at: nil }), success: "Schedule removed"
      end

      at, error = requested_schedule
      return refuse_schedule(error, editor) if error

      redirect_after Posts::Save.call(@post, attributes: { published_at: at }), success: "Scheduled"
    end

    private

    # Through the read scope (design spec §3.3): someone else's post an
    # author may not read is a 404 -- for show, autosave, publish and delete
    # alike -- not a 403 that would confirm it exists (Review Focus 2).
    def set_post
      @post = admin_scope(Post.all).find(params[:id])
    end

    def render_new_post_failure
      form = Admin::EditorScreen::NewPostFormComponent.new(
        url_options: admin_url_options, locale: admin_locale, content_type: params.dig(:post, :content_type),
        title: params.dig(:post, :title), errors: @post.errors
      )

      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace(form.form_id, form), status: :unprocessable_entity }
        format.html { render :new, status: :unprocessable_entity }
      end
    end

    # The list's own query params, the ones its links carry (`list_params`).
    # `status` is the old name of `scope` (the dashboard's "All drafts" links
    # and bookmarks used `status=draft|scheduled|live`): still read, `scope`
    # wins when both are there.
    LIST_KEYS = %i[q scope status type tag translation page].freeze
    SCOPES = %w[all live drafts scheduled].freeze

    def list_scope
      requested = params[:scope].presence || params[:status].presence
      requested = "drafts" if requested == "draft"
      requested.presence_in(SCOPES) || "all"
    end

    # Everything except the scope: the base the segmented control's counts
    # are taken over ("counts respect the other filters, not the scope
    # itself"), and what `filtered_posts` then narrows by scope.
    def base_posts
      scope = admin_scope(Post.all)
      scope = scope.where(content_type: params[:type]) if params[:type].is_a?(String) && params[:type].present?
      # A subquery, not `scope.joins(:tags).where(tags: { name: ... })`
      # directly (final-fixes round, finding 6): `.includes(:tags)` combined
      # with a `where` that references the same `tags` table is exactly what
      # makes Rails silently upgrade that `includes` into an `eager_load` (a
      # single LEFT OUTER JOIN) -- and once the *listing* query's own join is
      # filtered down to just the matching tag, that's also all `post.tags`
      # sees for the rest of that row, not every tag the post actually has.
      # Filtering by a subquery's `id`s instead leaves the outer scope with no
      # `tags` reference of its own, so `includes` stays a real `includes`.
      scope = scope.where(id: Post.joins(:tags).where(tags: { name: params[:tag] }).select(:id)) if params[:tag].is_a?(String) && params[:tag].present?
      scope = filter_by_translation(scope, params[:translation]) if params[:translation].is_a?(String)
      scope = filter_by_title(scope, params[:q]) if params[:q].is_a?(String) && params[:q].present?
      scope
    end

    def filtered_posts = filter_by_scope(base_posts, @scope)

    def page_of_posts
      filtered_posts.order(updated_at: :desc, id: :desc).offset(@pagination.offset).limit(PER_PAGE).to_a
    end

    def filter_by_scope(scope, name)
      case name
      when "live" then scope.published
      when "scheduled" then scope.where("posts.published_at > ?", Time.current)
      when "drafts" then scope.where(published_at: nil)
      else scope
      end
    end

    # "All 128 · Live 96 · Drafts 20 · Scheduled 12": one query for the four
    # numbers (`COUNT ... FILTER`), over `base_posts` -- the other filters
    # apply, the scope itself does not. The same instant is bound for both
    # comparisons so a post can't be counted as live and scheduled at once.
    def scope_counts
      now = Time.current
      all, live, drafts, scheduled = base_posts.reorder(nil).pick(
        Arel.sql("COUNT(*)"),
        Arel.sql(Post.sanitize_sql_array([ "COUNT(*) FILTER (WHERE posts.published_at <= ?)", now ])),
        Arel.sql("COUNT(*) FILTER (WHERE posts.published_at IS NULL)"),
        Arel.sql(Post.sanitize_sql_array([ "COUNT(*) FILTER (WHERE posts.published_at > ?)", now ]))
      )
      { "all" => all, "live" => live, "drafts" => drafts, "scheduled" => scheduled }
    end

    # `needs` (missing or outdated in any target language), `outdated`, or
    # `complete` (neither, in every target language), read from the stored
    # `translation_states` rows -- a post with no row reads as complete, the
    # same rule `Translations::StateIndex` applies everywhere. An EXISTS over
    # the target languages rather than `StateIndex.joins`, which narrows by
    # one language: this filter asks about the post as a whole.
    def filter_by_translation(scope, name)
      states = { "needs" => %w[missing outdated], "outdated" => %w[outdated] }[name]
      return scope unless states || name == "complete"

      exists = Translations::State.where(record_type: Post.polymorphic_name, locale: Translations.target_locales.map(&:to_s))
        .where("translation_states.record_id = posts.id")
        .where(state: states || %w[missing outdated]).arel.exists
      states ? scope.where(exists) : scope.where.not(exists)
    end

    def filter_by_title(scope, q)
      scope.where("posts.title ->> ? ILIKE ?", admin_locale, "%#{Post.sanitize_sql_like(q)}%")
    end

    # Each listed post's current public path in the editing language, locale
    # prefix included, in ONE query for the page (`PublicSite::Urls#path_for`
    # would ask once per post). A post no page lists has no row: "Not listed".
    def listed_paths(posts)
      return {} if posts.empty?

      prefix = PublicSite::Urls.new.prefix(admin_locale)
      PublicPath.current.where(record_type: Post.polymorphic_name, record_id: posts.map(&:id), locale: admin_locale)
        .pluck(:record_id, :path).to_h { |id, path| [ id, "#{prefix}#{path}" ] }
    end

    # The ids a bulk request names: an Array of Strings, nothing else (a
    # forged `ids[a]=b` hash or nested array is no selection at all).
    def bulk_ids
      raw = params[:ids]
      raw.is_a?(Array) ? raw.grep(String) : []
    end

    # Where a bulk request came from, read from the form's own hidden fields
    # (a POST's params are not `request.query_parameters`, which is what
    # `list_params` reads) -- the same keys, plain strings only, plus the
    # editing locale.
    def list_query = admin_url_options.merge(list_filters.symbolize_keys)

    def list_filters
      params.to_unsafe_h.slice(*LIST_KEYS.map(&:to_s)).select { |_, value| value.is_a?(String) }
    end

    def posts_list_path = admin_posts_path(**list_query)

    # A request no screen of ours sends (a forged action, more ids than the
    # list can show): a plain 422, no redirect to a list that did nothing.
    def refuse_bulk(message) = render(plain: message, status: :unprocessable_entity)

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
    #
    # The chip input (`Admin::ChipInputComponent`) submits `post[tag_names][]`
    # instead -- one element per tag, plus an empty sentinel so an emptied list
    # still arrives.
    #
    # An element is split on commas too (defence in depth): the chip input
    # already splits pasted text before it makes a chip, and a client that
    # sent "ruby, rails" as one element means two tags, same as the string.
    # Anything that is neither a String nor an Array of Strings (a hash, nested
    # arrays) answers nil -- "no usable tag list", so `update` leaves the tags
    # alone rather than clearing them; non-String elements of an Array are ignored.
    def split_tag_names(raw)
      parts = case raw
      when String then [ raw ]
      when Array then raw.grep(String)
      end
      return nil unless parts
      parts.flat_map { |part| part.split(",") }.map(&:strip).reject(&:blank?)
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
        # that point) -- wired up anyway so `Admin::ChipInputComponent`'s own
        # error slot (fix round 1 review) is always cleared/replaced like
        # every other field's, and a later validation on this attribute
        # (e.g. rejecting a tag name that's too long) has somewhere to land
        # without a second wiring pass.
        tag_names: [ "tag_names" ],
        # `Posts::Save#assign_related_posts`' unknown-id error, in
        # `Admin::RelatedPostsComponent`'s own slot.
        related_post_ids: [ "related_post_ids" ]
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
        forbidden_or(result) { redirect_to admin_post_path(@post, **admin_url_options), status: :see_other, alert: result.errors.to_sentence }
      end
    end
  end
end
