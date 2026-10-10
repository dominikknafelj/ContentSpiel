module Presence
  # One tab on one record (presence spec §5.2). The record is found through
  # the read scope, and a rejection says nothing about why, by
  # `Live::RecordChannel`; nothing is written for a record that is not found.
  # This class names the stream, writes the tab's row and says what
  # changed.
  #
  # PARAMS: `type` and `id` (the record), and `tab`, the tab's id in the shape
  # `Live::Signals::TAB` allows (a tab with no such id is rejected, before
  # anything is looked up or written).
  #
  # ACTIONS, the only two public methods: `report(state)` and `beat(state?)`.
  # Everything else is private because Action Cable lets a client call any
  # public method of the class (`test/channels/live/record_channel_test.rb`).
  #
  # THE TAB'S CONTRACT (the script of the next task):
  # - it REPORTS ITS STATE ON EVERY `connected`, the first time and after every
  #   reconnect: an arrival says "here", and a hidden or idle tab that
  #   reconnects would otherwise be shown as here until its next change;
  # - it reports a change at once (`report`, `data["state"]` "here" or "away";
  #   anything else is ignored) and beats every 30 seconds (`beat`), with its
  #   current state (`data["state"]`) so that a row lost for any reason is
  #   put back as what the tab is, not as "here";
  # - it never sends `leave`: closing, leaving the screen or dropping is the
  #   subscription's `unsubscribed`.
  #
  # THE SUBSCRIPTION OWNS ITS ROW by a token (`Presence::Mark`): leaving
  # deletes only the row this subscription wrote, so a reconnect whose old
  # connection is noticed dead later does not take the new subscription's row
  # with it. And a keep-alive or a report that finds no row (any cause:
  # swept, deleted, a late leave) re-creates it with the subscription's token
  # and the state last reported (`@state`) and signals, so a person who is
  # there is back within one keep-alive. A subscription that HAS LEFT heals
  # nothing (`unsubscribed`).
  #
  # Arriving writes the row and signals; leaving signals only when it deleted
  # a row; a change of state signals only when it was one (the channel
  # remembers the state it last reported); a beat that finds its row signals
  # nothing.
  #
  # NOT THROTTLED. A client may send `report` and `beat` as fast as it likes:
  # each is one indexed UPDATE, and a `report` that changes the state also two
  # broadcasts. A minimum interval per subscription is a later task (roadmap).
  class Channel < Live::RecordChannel
    # The tab says its state: "away" or "here". Anything else is ignored.
    def report(data)
      return if left?

      state = state_of(data)
      apply(state) if @record && state
    end

    # The tab is still here (`data["state"]`: what it is now; absent or
    # unknown, what it last reported).
    def beat(data)
      return if left? || !@record

      state = state_of(data) || @state
      return apply(state) if state != @state

      heal(state) unless Mark.beat(user: @user, record: @record, tab: @tab)
    end

    private

    def subscribed
      @tab = params[:tab].to_s[Live::Signals::TAB]
      return reject unless @tab

      super
    end

    def arrived(record)
      @user = subscriber
      @record = record
      @state = "here"
      @token = Mark.arrive(user: @user, record:, tab: @tab)
      Signals.changed(record)
    end

    def stream_name_for(record) = Signals.record_stream(record)

    # The record is the one found at subscribe time: it may have been trashed
    # since, and its row is still this subscription's to take away.
    #
    # `@left` is set FIRST, before the row is deleted. Action Cable hands each
    # of a connection's commands to a pool of threads and takes a
    # subscription out of its list only after this method has returned, so a
    # `beat` or a `report` sent in the same moment as the leave can still be
    # worked on this object, find no row and put one back (`heal`), with
    # nobody left to delete it: the person would be shown for as long as a
    # row stays fresh. Once it has left, a subscription writes nothing and
    # tells nobody: `report` and `beat` return at once, and `heal` asks again
    # for the action that had already passed that check when the leave began.
    def unsubscribed
      @left = true
      return unless @record

      Signals.changed(@record) if Mark.leave(user: @user, record: @record, tab: @tab, token: @token)
    end

    def state_of(data)
      state = data.is_a?(Hash) ? data["state"] : nil
      state if Presence::STATES.include?(state)
    end

    # The tab's state is `state`: write it, and say so if it is not what the
    # others were told.
    def apply(state)
      changed = state != @state
      @state = state
      if Mark.report(user: @user, record: @record, tab: @tab, state:)
        Signals.changed(@record) if changed
      else
        heal(state)
      end
    end

    def left? = @left == true

    def heal(state)
      return if left?

      @state = state
      Mark.arrive(user: @user, record: @record, tab: @tab, token: @token, state:)
      Signals.changed(@record)
    end
  end
end
