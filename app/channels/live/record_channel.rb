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
  # A subclass defines `stream_for(record)` -> String, and may define
  # `arrived(record)`, called once the stream is open.
  class RecordChannel < ApplicationCable::Channel
    def subscribed
      user = subscriber
      record = user && RecordKinds.find(params[:type], user, params[:id])
      return reject unless record

      stream_from stream_for(record)
      arrived(record) if respond_to?(:arrived, true)
    end
  end
end
