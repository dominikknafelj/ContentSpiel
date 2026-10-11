module Editing
  # The one audited write of live editing (live-editing spec §4.4): a subject
  # passes from the tab that holds it to someone who asked for it.
  #
  # THE REQUESTER'S CALL (`hand_over: false`), in this order:
  # 1. its own request is `Editing::PASS_OVER` old, was not answered and the
  #    hold is still live: the row is passed over, on what was saved
  #    (`answered: false`), and audited;
  # 2. another tab holds the subject live: the request is written on its row
  #    and that tab is told (`requested`). It drains its write queue and calls
  #    this service with `hand_over: true`. If another tab's request stands
  #    (the first requester keeps it) the answer is `pending`;
  # 3. nobody holds it live: the tab simply claims.
  #
  # THE HOLDER'S CALL (`hand_over: true`) passes the row to whoever asked
  # (`answered: true`). The holder needs the right as well: someone who lost
  # it since cannot hand over (denied, the row stays as it was), and the
  # requester's second call, PASS_OVER after the first, takes the row.
  #
  # EVERY COMBINATION (the asker against the row as it stands at `now`):
  #
  #   requester's call
  #   no row, or an expired one ............................ claimed
  #   a live row of THIS tab ............................... claimed (renewed, no signal)
  #   a live row of another tab, no request ................ requested (written, holder told)
  #   ... with this tab's request, younger than PASS_OVER .. requested (time kept, holder told again)
  #   ... with this tab's request, PASS_OVER old or older .. taken (audited, answered: false)
  #   ... with this tab's request older than 2 * PASS_OVER . taken too (a pass-over is due from PASS_OVER on)
  #   ... with another tab's request, younger than
  #       2 * PASS_OVER .................................... pending (nothing changes, nothing is sent)
  #   ... with another tab's request, 2 * PASS_OVER or older  requested (replaces it: its tab is gone)
  #   the holder's user deleted ............................ the row went with the user: no row
  #   the holder lacks the right now ....................... as any live row: the requester does not
  #                                                          need the holder's right, only its own
  #
  #   holder's call (hand_over: true)
  #   this tab holds it live and a request stands .......... handed (audited, answered: true)
  #   this tab holds it, nobody asked (or the requester's
  #   user was deleted, which nullifies the request) ....... nothing
  #   another tab holds it, no row, an expired row,
  #   a row already passed over ............................ nothing
  #   the holder lacks the right ........................... denied (access.denied), the row is untouched
  #
  # A RELEASE with a request pending deletes the row and the request with it:
  # the requester's next call finds no row and claims (`claimed`).
  #
  # THE SAME PERSON'S OTHER TAB taking over from themselves is audited like any
  # other transfer (both ids are the same person's): it is still a hold that
  # moved between tabs, and the log should be able to say so.
  #
  # The statements run in one short transaction, with the subject's row locked
  # first so the answer is about the row the statements then change; the event
  # is written in it, the signal goes out after the outermost commit. The
  # event is on the content record and holds two ids and a flag: no name, no
  # text, no snapshot. It is not a change of content (`Dashboard::Feed::
  # NOT_A_CHANGE`): no content row is written, nothing a stale check reads
  # moves.
  #
  # LOCKS: the subject's own reservation row (`FOR UPDATE`), nothing else:
  # never a content row, and no other service names `Editing::`, so no cycle
  # with a content write. It is one short transaction (one locking read, up to
  # four statements, one audit insert), and nothing is sent or rendered inside
  # it: the signal and the audit notification go out after the outermost
  # commit. With no row there is nothing to lock and the unique index settles
  # the race: the loser's claim is refused and it asks the winner. If both
  # lost races leave no request standing, the call answers what is true of the
  # row after the retry, never `pending` without a request.
  #
  # LEFT AS IT IS: `Users::Destroy` of the REQUESTER while a transfer of that
  # person's request runs could deadlock (the transfer's UPDATE checks the
  # user row that the destroy holds while it waits to nullify the
  # reservation); Postgres aborts one of them. It needs an admin deleting
  # someone mid-take-over, and the single statements `hand_over` and
  # `pass_over` have the same cycle with or without this lock.
  class TakeOver < ApplicationService
    PREFIX = { "ContentBlock" => "block", "Page" => "page", "Post" => "post" }.freeze

    attr_reader :outcome

    def initialize(subject, record:, tab:, hand_over: false, actor: Current.actor)
      @subject = subject
      @record = record
      @tab = tab.to_s[Live::Signals::TAB]
      @hand_over = hand_over
      @actor = actor
    end

    def call
      refused = AccessControl::OwnerRule.refusal(@record) { |key| authorize!(key, @record) }
      return denied(refused, @record) if refused

      user = actor_user
      return failure(@subject, [ "Taking over needs a signed-in person and a browser tab." ]) unless user.is_a?(User) && @tab

      now = Time.current
      Reservation.transaction do
        @row = Reservation.of(@subject).lock.first
        @hand_over ? hand_over(user, now) : take(user, now)
      end
      success(@subject)
    end

    private

    def live?(row, now) = row && row.changed_at > now - Editing::HOLD

    def take(user, now)
      if live?(@row, now) && Reservation.pass_over(subject: @subject, by: user, tab: @tab, now:)
        return passed(from: @row.user_id, to: user.id, answered: false, outcome: :taken)
      end

      3.times do
        case Reservation.request(subject: @subject, by: user, tab: @tab, now:)
        when :requested
          @outcome = :requested
          return Signals.holder(@record, @subject, "requested")
        when :pending
          return @outcome = :pending
        end

        claimed = Reservation.claim(subject: @subject, record: @record, user:, tab: @tab, now:)
        next if claimed == :refused # someone claimed it between the two statements: ask them instead

        Signals.holder(@record, @subject, "claimed") if claimed == :taken
        return @outcome = :claimed
      end
      # Three lost races in a row cannot leave a live row of another tab
      # without a request standing (a request would have been written), so this
      # is reached only by a row that changed under us again: say what is true
      # of it now.
      @outcome = settled_outcome(user, now)
    end

    def settled_outcome(user, now)
      row = Reservation.of(@subject).live(now).first
      return :claimed if row.nil? || (row.user_id == user.id && row.tab == @tab)
      return :requested if row.requested_by_id == user.id && row.requested_tab == @tab

      row.requested? ? :pending : :requested
    end

    def hand_over(user, now)
      mine = live?(@row, now) && @row.user_id == user.id && @row.tab == @tab && @row.requested?
      return @outcome = :nothing unless mine && Reservation.hand_over(subject: @subject, user:, tab: @tab, now:)

      passed(from: user.id, to: @row.requested_by_id, answered: true, outcome: :handed)
    end

    def passed(from:, to:, answered:, outcome:)
      @outcome = outcome
      record_event("#{PREFIX.fetch(@subject.class.name)}.taken_over", subject: @subject, snapshot: nil, coalesce: false,
        metadata: { "from_user_id" => from, "to_user_id" => to, "answered" => answered })
      Signals.holder(@record, @subject, "taken")
    end
  end
end
