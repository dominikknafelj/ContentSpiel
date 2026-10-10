module Presence
  # What presence says, and to whom (presence spec §5.2). A signal says THAT
  # presence changed -- never who: a tab showing the record fetches its
  # people again, a tab showing a list fetches its markers again, and both
  # fetches are scoped (`Admin::PresenceController`), so the list's stream
  # tells nobody anything they could not ask. The sending is
  # `Live::Signals`', after the outermost commit.
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
      kind = RecordKinds.of(record) or raise ArgumentError, "no record kind for #{record.class.polymorphic_name}"
      Live::Signals.later(record_stream(record), { kind: "presence" })
      Live::Signals.later(LIST, { kind: "presence", record: [ kind.name, record.id ] })
    end
  end
end
