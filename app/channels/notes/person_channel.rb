module Notes
  # One person's stream (notes spec §6.2): "something was addressed to you".
  # It takes no parameter: the user is the connection's, identified from the
  # CS Studio session like every controller, so nobody can ask for someone
  # else's. Whatever a subscription sends along is not read.
  class PersonChannel < ApplicationCable::Channel
    def subscribed
      stream_from Signals.person_stream(current_user.id)
    end
  end
end
