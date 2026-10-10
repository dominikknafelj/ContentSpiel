module Admin
  # The two reads of presence (presence spec §5.3), both through the read
  # scope: who else has this record open, and which of a list's records have
  # someone here. A class, never `Admin::Presence`, which would shadow
  # `Presence::`. It only reads: the writes are the channel's.
  class PresenceController < BaseController
    include RecordOfKind

    # How many ids a list may ask about at once; the rest are ignored.
    MAX_IDS = 500

    # Who is on a record changes from one second to the next: neither answer
    # is kept by any cache, the browser's included (a fetch that was answered
    # from one would show who was here a minute ago).
    before_action { response.set_header("Cache-Control", "no-store") }

    # The people of one record, the viewer left out: `turbo-frame#presence-
    # <kind>-<id>` as `Admin::PresenceScreen::PeopleComponent` draws it, at
    # the header's size or, with `size=panel`, the media panel's (anything
    # else is the header's). The tab's script fetches it with a plain `fetch`
    # that names the frame (`Turbo-Frame`), and is answered with the frame
    # alone; asked for as a page, it is the frame in the layout. A record
    # outside the scope or in the trash is a 404 (an image without
    # `media.upload`, the 403 notes gives).
    def show
      @record = record_of_kind(params[:kind], params[:id])
      return if performed?

      people = Admin::PresenceScreen::PeopleComponent.new(record: @record, viewer: Current.user, size: params[:size] == "panel" ? :panel : :header, frame_only: true)
      render people, layout: turbo_frame_request? ? false : "admin"
    end

    # `{ "<id>": <number of other people here> }` for those of the ids the
    # viewer may read and that have someone here. An id the viewer may not
    # read, a trashed one and one that is not there are the same silence, and
    # so is an unknown kind: `{}`.
    def here
      kind = RecordKinds.named(params[:kind])
      ids = Array.wrap(params[:ids]).grep(String).grep(/\A\d{1,18}\z/).uniq.first(MAX_IDS)
      return render(json: {}) unless kind && ids.any?

      # The asked ids narrowed through the kind's read scope as a subquery:
      # one statement counts the readable ones, and no record is loaded.
      readable = kind.readable_ids(Current.actor, channel: Current.channel).where(id: ids)
      render json: Presence::Roster.new(viewer: Current.user).here_counts(kind, readable).transform_keys(&:to_s)
    end
  end
end
