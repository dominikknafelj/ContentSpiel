module Editing
  # The stream of one page or post (live-editing spec §3.1), found through the
  # read scope at subscribe time and rejected alike for a record out of scope,
  # trashed, missing or of an unknown kind, by `Live::RecordChannel`. It
  # offers a client no action and writes nothing: both hooks are private.
  class Channel < Live::RecordChannel
    private

    # Only a page or a post has a stream: nothing is ever signalled for an
    # image, so there is nothing to subscribe to.
    def subscribed
      return reject unless %w[page post].include?(params[:type].to_s)

      super
    end

    def stream_name_for(record) = Signals.record_stream(record)
  end
end
