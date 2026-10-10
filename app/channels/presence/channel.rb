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
  # ACTIONS, the only two public methods: `report(state)` (the tab is hidden
  # or idle, or back) and `beat` (still here). Everything else is private
  # because Action Cable lets a client call any public method of the class
  # (`test/channels/live/record_channel_test.rb`).
  #
  # Arriving writes the row and signals; leaving (the socket closes, the tab
  # leaves the screen) deletes it and signals; a change of state signals only
  # when it was one; a beat signals nothing.
  class Channel < Live::RecordChannel
    # The tab says its state: "away" or "here". Anything else, and the same
    # state again, changes and says nothing.
    def report(data)
      return unless @record

      Signals.changed(@record) if Mark.report(user: @user, record: @record, tab: @tab, state: data.is_a?(Hash) ? data["state"] : nil)
    end

    # The tab is still here.
    def beat
      Mark.beat(user: @user, record: @record, tab: @tab) if @record
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
      Mark.arrive(user: @user, record:, tab: @tab)
      Signals.changed(record)
    end

    def stream_name_for(record) = Signals.record_stream(record)

    # The record is the one found at subscribe time: it may have been trashed
    # since, and its row is still this tab's to take away.
    def unsubscribed
      return unless @record

      Mark.leave(user: @user, record: @record, tab: @tab)
      Signals.changed(@record)
    end
  end
end
