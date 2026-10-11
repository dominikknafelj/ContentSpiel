module Editing
  # The stream of one page or post (live-editing spec §3.1), found through the
  # read scope at subscribe time and rejected alike for a record out of scope,
  # trashed, missing or of an unknown kind, by `Live::RecordChannel`. It
  # offers a client no action and writes nothing: both hooks are private.
  class Channel < Live::RecordChannel
    private

    def stream_name_for(record) = Signals.record_stream(record)
  end
end
