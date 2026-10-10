module Live
  # The base of a channel on one record (presence spec §4.2; notes spec
  # §6.2). The record is looked up THROUGH THE READ SCOPE at subscribe time
  # (`RecordKinds.find`), as `Admin::NoteContainer` does for a request, and a
  # record that is out of scope, in the trash, not there, of an unknown kind or
  # named by a bad id is rejected alike: a rejection says nothing about which
  # it was. The stream's name is built from the record that was found, never
  # from what was sent.
  #
  # The rights are the user's AT SUBSCRIBE TIME: `subscriber` is read afresh,
  # so an owner demoted since the socket connected is judged by their grants
  # and a user deleted since is rejected.
  #
  # A right that is taken away later needs no handling: a signal says nothing
  # (`Live::Signals`), and the fetch it leads to is scoped.
  #
  # THE HOOKS ARE PRIVATE, in a subclass as here. Action Cable lets a client
  # call any PUBLIC method a channel class defines itself (`action_methods`;
  # `dispatch_action` hands an arity-1 one the client's data), so a public
  # `arrived` -- which in presence writes a row -- or a public
  # `stream_name_for` would be a command anyone with a socket could send.
  # `test/channels/live/record_channel_test.rb` fails for a subclass under
  # `app/channels` that makes one public.
  #
  # A subclass defines, privately, `stream_name_for(record)` -> String (not
  # `stream_for`: that is Action Cable's own, for a model, and a subclass that
  # forgot the hook would silently get it), and may define `arrived(record)`.
  # `arrived` runs BEFORE the stream is opened, so one that raises leaves
  # nothing open and the subscription is never confirmed.
  #
  # `subscribed` is private as well: Action Cable calls it from inside
  # (`subscribe_to_channel`), and a public one is an action a client could send
  # again, running `arrived` a second time.
  class RecordChannel < ApplicationCable::Channel
    private

    def subscribed
      user = subscriber
      record = user && RecordKinds.find(params[:type], user, params[:id])
      return reject unless record

      arrived(record) if respond_to?(:arrived, true)
      stream_from stream_name_for(record)
    end

    def stream_name_for(record)
      raise NotImplementedError, "#{self.class.name} must define a private stream_name_for(record)"
    end
  end
end
