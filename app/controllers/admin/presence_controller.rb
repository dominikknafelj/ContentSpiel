module Admin
  # The two reads of presence (presence spec §5.3), both through the read
  # scope: who else has this record open, and which of a list's records have
  # someone here. A class, never `Admin::Presence`, which would shadow
  # `Presence::`. It only reads: the writes are the channel's.
  class PresenceController < BaseController
    include RecordOfKind

    # How many ids a list may ask about at once; the rest are ignored.
    MAX_IDS = 500

    # The people of one record, the viewer left out: `turbo-frame#presence-
    # <kind>-<id>` holding one element per person, `data-presence-user` (the
    # user's id) and `data-presence-state` ("here" or "away"). The inside is
    # an interim list; the frame's id and those two attributes are what the
    # screens' script and tests rely on. A record outside the scope or in the
    # trash is a 404 (an image without `media.upload`, the 403 notes gives).
    def show
      @record = record_of_kind(params[:kind], params[:id])
      return if performed?

      @frame_id = "presence-#{params[:kind]}-#{@record.id}"
      @people = Presence::Roster.new(viewer: Current.user).on(@record)
      render layout: turbo_frame_request? ? false : "admin"
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
