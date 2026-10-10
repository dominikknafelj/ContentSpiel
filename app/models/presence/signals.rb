module Presence
  # What presence says, and to whom (presence spec §5.2). A signal says THAT
  # presence changed -- never who, and on the list stream never WHERE: a tab
  # showing the record fetches its people again, a tab showing a list fetches
  # all its markers again, and both fetches are scoped
  # (`Admin::PresenceController`).
  #
  # THE LIST SIGNAL NAMES NO RECORD. Its stream is open to every signed-in
  # user, whatever they may read, so a signal that said "post 812" would tell
  # someone with no grant on posts that post 812 exists and that somebody is
  # on it now -- the very thing every other door answers alike for "missing"
  # and "not yours". What a list tab hears is "somebody did something
  # somewhere"; it fetches its own rows through the read scope, at most once
  # per interval. The sending is `Live::Signals`', after the outermost commit.
  #
  # A record's stream is named by its polymorphic type without the colons
  # ("MediaAsset-5"), written here again rather than taken from notes, which
  # presence does not know.
  module Signals
    LIST = "presence:list".freeze

    module_function

    def record_stream(record) = "presence:record:#{record.class.polymorphic_name.delete(":")}-#{record.id}"

    # Somebody arrived at, left or changed state on this record.
    def changed(record)
      Live::Signals.later(record_stream(record), { kind: "presence" })
      Live::Signals.later(LIST, { kind: "presence" })
    end
  end
end
