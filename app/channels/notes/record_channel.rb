module Notes
  # One record's stream (notes spec §6.2): "a thread of this page, post or
  # image changed". The container is looked up THROUGH THE READ SCOPE at
  # subscribe time, as `Admin::NoteContainer` does for a request, and a
  # record that is out of scope, in the trash or not there is rejected alike:
  # a rejection says nothing about which it was. The stream's name is built
  # from the record that was found, never from what was sent.
  #
  # The rights are the user's AT SUBSCRIBE TIME: `subscriber` is read afresh,
  # so an owner demoted since the socket connected is judged by their grants
  # and a user deleted since is rejected.
  #
  # A right that is taken away later needs no handling: the signal says
  # nothing (`Notes::Signals`), and the fetch it leads to is scoped.
  class RecordChannel < ApplicationCable::Channel
    def subscribed
      container = find_container
      container ? stream_from(Signals.record_stream(container.class.polymorphic_name, container.id)) : reject
    end

    private

    # Digits only, and few enough to be a bigint: anything else names no
    # record, and must not reach the query as a string Postgres would have
    # to refuse.
    def find_container
      id = params[:id].to_s[/\A\d{1,18}\z/] or return
      user = subscriber or return

      case params[:type]
      when "page" then AccessControl.scope(user, "pages.read", Page.where(id: id), channel: :admin).first
      when "post" then AccessControl.scope(user, "posts.read", Post.where(id: id), channel: :admin).first
      when "media" then (Media::Asset.kept.find_by(id: id) if AccessControl.holds?(user, "media.upload", channel: :admin))
      end
    end
  end
end
