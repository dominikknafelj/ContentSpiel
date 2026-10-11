module Notes
  # One person's stream (notes spec §6.2): "something was addressed to you".
  # It takes no parameter: the user is the connection's, identified from the
  # CS Studio session like every controller, so nobody can ask for someone
  # else's. Whatever a subscription sends along is not read. A socket whose
  # session has ended, or whose user is gone, is rejected
  # (`ApplicationCable::Channel#subscriber`).
  class PersonChannel < ApplicationCable::Channel
    private

    # Private: a public method of a channel is an action a client may send.
    def subscribed
      subscriber ? stream_from(Signals.person_stream(subscriber.id)) : reject
    end
  end
end
