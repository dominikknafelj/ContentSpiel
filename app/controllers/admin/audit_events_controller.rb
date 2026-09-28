module Admin
  # The audit log (access-control design spec §5 "Audit log module",
  # Task 9): a paginated list of every `Audit::Event`, filterable by
  # user/action/subject/date range, plus each event's own page.
  #
  # Unlike every other admin module, this one is never read-scoped by
  # content (Task 9 controller ruling): `audit.view` is an
  # administration-area permission (design spec §3.1) that the seeded set
  # gives only to Admin, so whoever can open this screen at all sees every
  # event -- there is no "my own events only" reading of it, and `index`/
  # `show` load straight from `Audit::Event`, not through `admin_scope`.
  # What *is* still scoped is where a row's subject link goes:
  # `Admin::AuditEventsHelper#audit_subject_path` only links to a post or
  # page the current viewer can still read (Review Focus 2 -- a record's
  # existence is never disclosed through a wider door than its own editor
  # already opens), falling back to the plain `subject_label` otherwise.
  class AuditEventsController < BaseController
    PER_PAGE = 50

    # The subject types any cataloged event (design spec §4.3) can carry,
    # keyed by the polymorphic `subject_type` string actually stored on
    # the row -- `AccessControl::Group`'s own table-name comment explains
    # why its own type is the full namespaced name, not "Group". This is
    # the filter's whitelist (Task 9 brief: "subject_type among known
    # types ... invalid -> ignored, no 500") and the index view's own
    # <select>, so the two can't silently drift apart about what "known"
    # means; `AuditEventsHelper#audit_subject_path` matches the same
    # literals for the same reason.
    SUBJECT_TYPES = {
      "Post" => "Post",
      "Page" => "Page",
      "ContentBlock" => "Block",
      "AccessControl::Group" => "Group",
      "Tag" => "Tag",
      "User" => "User",
      "SiteSetting" => "Settings",
      "ApiToken" => "API token",
      "MediaAsset" => "Media asset"
    }.freeze

    before_action -> { require_permission("audit.view") }

    # Filters as query params (mirrors `Admin::PostsController#index`'s own
    # comment about its own filters): `user_id` is a `User` id,
    # `event_action` the bare catalogue string (design spec §4.3) -- named
    # `event_action`, not the more obvious `action`, because `params
    # [:action]` is Rails' own routing parameter (the controller action,
    # "index"/"show") and would silently shadow it, matching nothing ever
    # again -- `subject_type`/`subject_id` narrow to one record (exactly
    # what the Activity link on a post/page/user editor sends), and
    # `from`/`to` an inclusive date range in plain `YYYY-MM-DD`. Every one
    # of them is validated here rather than trusted straight into a
    # `where`: an invalid or unknown value is silently dropped from the
    # scope, never a 500 (Task 9 brief).
    #
    # Pagination is plain `limit`/`offset` (Task 9 brief: "use the
    # existing pattern if there is one, else simple limit/offset [50]") --
    # no other CS Studio list paginates at all (every other one renders in
    # full), so there's no existing pattern to follow. Fetching one extra
    # row (`PER_PAGE + 1`) is how `@has_next` is known without a second
    # `count` query; Next/Previous rather than page numbers, since an
    # offset alone can't render a reliable page count against a log that
    # keeps growing underneath a paged-back visitor.
    def index
      @events = filtered_events.recent.includes(:subject, :user).limit(PER_PAGE + 1).offset(offset).to_a
      @has_next = @events.size > PER_PAGE
      @events = @events.first(PER_PAGE)
      @offset = offset
      @users = User.order(:email_address)
      @actions = Audit::Event.distinct.order(:action).pluck(:action)
      @subject_types = SUBJECT_TYPES
    end

    def show
      @event = Audit::Event.includes(:subject, :user).find(params[:id])
    end

    private

    def offset
      raw = params[:offset].to_i
      raw.positive? ? raw : 0
    end

    def filtered_events
      scope = Audit::Event.all
      scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?
      scope = scope.where(action: params[:event_action]) if params[:event_action].present?
      scope = scope.where(subject_type: params[:subject_type]) if SUBJECT_TYPES.key?(params[:subject_type])
      # `subject_id` alone, without a valid `subject_type`, is ambiguous
      # (a `Post` and a `Page` can share the same id) -- ignored rather
      # than matched against every type at once.
      scope = scope.where(subject_id: params[:subject_id]) if params[:subject_id].present? && SUBJECT_TYPES.key?(params[:subject_type])
      scope = scope.where(occurred_at: from_date..) if from_date
      scope = scope.where(occurred_at: ..to_date) if to_date
      scope
    end

    def from_date = @from_date ||= parsed_date(params[:from])&.beginning_of_day

    def to_date = @to_date ||= parsed_date(params[:to])&.end_of_day

    # `Date.iso8601` raises on anything that isn't a real `YYYY-MM-DD`
    # date (a typo, a stray query param, a probing request) -- caught
    # here so a malformed filter never reaches the visitor as a 500
    # (Task 9 brief).
    def parsed_date(value)
      return nil if value.blank?

      Date.iso8601(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
