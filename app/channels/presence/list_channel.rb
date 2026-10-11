module Presence
  # The one stream every list listens on (presence spec §5.2): "presence
  # changed somewhere" (`Presence::Signals`, `{ kind: "presence" }`). Any
  # signed-in user may listen, which is why the signal names no record and
  # nobody: it tells a person nothing about a record they may not read, and
  # the markers a tab fetches after it are scoped. `subscribed` is private
  # because a public method of a channel is an action a client may send.
  class ListChannel < ApplicationCable::Channel
    private

    def subscribed
      subscriber ? stream_from(Signals::LIST) : reject
    end
  end
end
