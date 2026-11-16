module Media
  # The one stream of the media library (`Media::LibrarySignals`). Whoever may
  # read library images (`media.upload`, the read right of the "media" record
  # kind) may listen, judged as the user is NOW; anyone else, and a socket
  # with no user, is rejected alike. `subscribed` is private because a public
  # method of a channel is an action a client may send.
  class LibraryChannel < ApplicationCable::Channel
    private

    def subscribed
      user = subscriber
      return reject unless user && AccessControl.holds?(user, RecordKinds.named("media").read)

      stream_from LibrarySignals::STREAM
    end
  end
end
