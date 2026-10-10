module Presence
  # The one stream every list listens on (presence spec §5.2): "presence
  # changed on this record" (`Presence::Signals`, `{ kind, record: [kind, id] }`).
  # Any signed-in user may listen: the signal names a record and nobody, and
  # the markers a tab fetches after it are scoped. `subscribed` is private
  # because a public method of a channel is an action a client may send.
  class ListChannel < ApplicationCable::Channel
    private

    def subscribed
      subscriber ? stream_from(Signals::LIST) : reject
    end
  end
end
