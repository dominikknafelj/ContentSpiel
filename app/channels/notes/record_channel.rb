module Notes
  # One record's stream (notes spec §6.2): "a thread of this page, post or
  # image changed". Finding the record through the read scope, the rejection
  # and the user as they are now are `Live::RecordChannel`'s; this names the
  # stream. A signal on it says nothing (`Notes::Signals`), and the fetch it
  # leads to is scoped.
  class RecordChannel < Live::RecordChannel
    def stream_for(record) = Signals.record_stream(record.class.polymorphic_name, record.id)
  end
end
