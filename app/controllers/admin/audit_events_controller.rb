module Admin
  # The audit log (access-control design spec §5 "Audit log module"; design pass
  # round 3, Task 15): every `Audit::Event` under day headers, each told as a
  # sentence (`Audit::Sentence`), filterable by user, action, type, channel and
  # a date preset (`Audit::Filter`), plus each event's own page with its field
  # changes as word diffs and Older/Newer through the same filtered list.
  #
  # Unlike every other admin module, this one is never read-scoped by content
  # (Task 9 controller ruling): `audit.view` is an administration-area
  # permission (design spec §3.1) that the seeded set gives only to Admin, so
  # whoever can open this screen at all sees every event -- there is no "my own
  # events only" reading of it, and `index`/`show` load straight from
  # `Audit::Event`, not through `admin_scope`. The DISCLOSURE is unchanged from
  # before the redesign: an event's stored label (a title) shows for every
  # event, a record the viewer can't read included. What is still scoped is
  # where a subject LINKS: `Audit::Sentence::Targets` links a post or page only
  # when the viewer can read it (decided for the whole page of events at once,
  # not per row), a user, group or the settings only to the right to manage
  # them, and everything else (a deleted record, a block, a tag) is plain text.
  #
  # Filters as query params: `user_id` is a `User` id, `event_action` the bare
  # catalogue string -- named `event_action`, not the more obvious `action`,
  # because `params[:action]` is Rails' own routing parameter (the controller
  # action, "index"/"show") and would silently shadow it -- `subject_type` +
  # `subject_id` narrow to one record (exactly what the Activity link on a
  # post/page/user editor sends), `channel`, and `range` (+ `from`/`to` for a
  # custom one). Each is validated by `Audit::Filter`; an invalid value is
  # dropped, never a 500.
  #
  # Pagination is `limit`/`offset` (round 3 decision D23): fetching one extra row
  # (`PER_PAGE + 1`) is how `@has_next` is known without a count, and Newer /
  # Load older rather than page numbers, since an offset alone can't give a
  # reliable page count against a log that keeps growing underneath a
  # paged-back visitor. The order is `last_occurred_at DESC, id DESC`
  # (`index_audit_events_on_recent`), which is also where a coalesced span sits.
  class AuditEventsController < BaseController
    PER_PAGE = 50
    # The User drop-down's cap (the chosen user is always included).
    MAX_USERS = 200
    # Actions the log holds that no sentence knows (a plugin's), for the Action
    # drop-down's "Other" group.
    MAX_OTHER_ACTIONS = 100

    before_action -> { require_permission("audit.view") }
    before_action :load_filter

    def index
      events = Audit::Filter.ordered(@filter.scope).includes(:user).limit(PER_PAGE + 1).offset(offset).to_a
      @has_next = events.size > PER_PAGE
      events = events.first(PER_PAGE)
      @offset = offset
      @entries = events.zip(Audit::Sentence.for_events(events, viewer: Current.actor, channel: Current.channel))
      @users = users_for_filter
      @other_actions = Audit::Event.where.not(action: Audit::Sentence::ACTIONS).distinct.limit(MAX_OTHER_ACTIONS).pluck(:action)
    end

    # An event outside the current filters is not found (the list the visitor
    # came from wouldn't show it), exactly as a missing id is.
    def show
      @event = @filter.scope.includes(:user).find(params[:id])
      @sentence = Audit::Sentence.for(@event, viewer: Current.actor, channel: Current.channel)
      @older_id = neighbour(@event, :older)
      @newer_id = neighbour(@event, :newer)
    end

    private

    def load_filter = @filter = Audit::Filter.new(params)

    def offset
      raw = params[:offset].to_i
      raw.positive? ? raw : 0
    end

    # The adjacent event in the list's own order (`last_occurred_at, id`,
    # newest first) within the current filters, one indexed query: a row
    # comparison on the very pair `index_audit_events_on_recent` is ordered by.
    def neighbour(event, direction)
      older = direction == :older
      scope = @filter.scope.where("(audit_events.last_occurred_at, audit_events.id) #{older ? "<" : ">"} (?, ?)", event.last_occurred_at, event.id)
      scope = older ? Audit::Filter.ordered(scope) : scope.order(last_occurred_at: :asc, id: :asc)
      scope.pick(:id)
    end

    def users_for_filter
      users = User.order(:email_address).limit(MAX_USERS).to_a
      chosen = @filter.user_id
      users << User.find_by(id: chosen) if chosen && users.none? { |user| user.id == chosen }
      users.compact
    end
  end
end
