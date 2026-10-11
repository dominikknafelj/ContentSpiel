module Admin
  # The two reads of presence (presence spec §5.3), both through the read
  # scope: who else has this record open, and which of a list's records have
  # someone here. A class, never `Admin::Presence`, which would shadow
  # `Presence::`. It only reads: the writes are the channel's.
  class PresenceController < BaseController
    include RecordOfKind

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

    # What a list's markers show (`admin--presence--list` asks):
    # `{ "<id>": { "count": 2,
    # "label": "2 people here: Dana Weiss, Jonas Lind" } }` for those of the
    # ids the viewer may read and that have someone else here. `label` names
    # the first five in order of arrival and says how many more; it is the
    # marker's one text, for a screen reader and the
    # tooltip alike (handoff 32), worded where the first drawing words it
    # (`Admin::PresenceScreen::RowMarkerComponent.words`), so the script
    # holds no wording and a marker reads the same before and after it.
    # A name is what a person typed: it is a JSON string here and text in
    # the page. An id the viewer may not read, a trashed one and one that
    # is not there are the same silence, and so is an unknown kind: `{}`.
    def here
      kind = RecordKinds.named(params[:kind])
      ids = Array.wrap(params[:ids]).grep(String).grep(/\A\d{1,18}\z/).uniq.first(Presence::HERE_IDS)
      return render(json: {}) unless kind && ids.any?

      # The asked ids narrowed through the kind's read scope as a subquery:
      # one statement reads who is here on the readable ones, a second their
      # users, and no record is loaded.
      readable = kind.readable_ids(Current.actor, channel: Current.channel).where(id: ids)
      here = Presence::Roster.new(viewer: Current.user).here_people(kind, readable)
      render json: here.to_h { |id, people| [ id.to_s, Admin::PresenceScreen::RowMarkerComponent.words(people) ] }
    end
  end
end
