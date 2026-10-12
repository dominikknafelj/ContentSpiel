module Admin
  # Publishing a page's or post's changes, discarding them and withdrawing a
  # scheduled change (drafts spec §4.3). A class, never a namespace:
  # `Admin::Publishing` would shadow `Publishing::` for every bare reference
  # inside `module Admin`.
  #
  # Every action finds its record through the read scope (`RecordOfKind`: out
  # of scope and trashed are a 404) and the services ask the rights. A
  # refusal the publish dialog can show travels as `flash[:publish_error]`,
  # not `flash[:alert]`: the header hands it to the dialog, which reopens
  # with it, as the Schedule dialog does with its own (`Admin::Scheduling`).
  class PublishingController < BaseController
    include RecordOfKind
    include EditingClaims
    include Scheduling

    SCOPE = "admin.components.editor_screen.publishing".freeze

    before_action :set_record

    # WHAT A PUBLISH WOULD CHANGE, for the dialog, asked when it opens.
    #
    # A POST, AND SENT THROUGH THE TAB'S WRITE QUEUE (`admin--editor--publish-dialog`),
    # for two reasons. The overview is true only once every save the tab has
    # outstanding has landed, and the queue is what orders them. And the
    # addresses a publish would take away or move are found by TRYING it
    # (`Publishing::Changes.addresses`: the record's row lock, a copy and
    # its addresses written inside a savepoint that is rolled back), which
    # must never run on a GET, where a prefetch or a crawler could hold a
    # page's lock against its editors.
    #
    # Nothing is kept: no row, no event, no signal. For anyone who may read
    # the record (it shows nothing the editor does not); the trial is made
    # only for someone who may publish, whose dialog it is.
    #
    # EVERY ANSWER SAYS WHAT IS SCHEDULED NOW (the pending copy's id and the
    # sentences that name its time): nothing a dialog says about a schedule
    # is from the page view. `part=schedule` answers that alone, with no
    # overview and no trial: what the discard and the cancel dialogs ask
    # when they open, one request per opening like the publish dialog's.
    def changes
      response.set_header("Cache-Control", "no-store")
      return render(Admin::EditorScreen::ChangesOverviewComponent.schedule_only(record: @record), layout: false) if params[:part] == "schedule"

      addresses = can?("#{kind}s.publish", @record) ? ::Publishing::Changes.addresses(@record) : ::PublicSite::Paths::Foreseen.nothing
      render Admin::EditorScreen::ChangesOverviewComponent.new(record: @record, changes: ::Publishing::Changes.of(@record), lost: addresses.lost, moved: addresses.moved,
        holds: ::Editing::Holds.on(@record, viewer: Current.user, tab: Current.editing_tab), locale: admin_locale, url_options: admin_url_options), layout: false
    end

    # Publishes now, at a time, or at the time the changes are already
    # scheduled for (`requested_time`). NOT refused while another tab holds a
    # part of the record: it writes no row an editor holds, and what is
    # published is what has been saved (the dialog says so, naming them).
    def publish
      at, error = requested_time
      return refuse_publish(error) if error

      before = ::Publishing.baseline(@record)&.number
      result = ::Publishing::PublishChanges.call(@record, at: at, shown_pending: shown_pending)
      return forbidden_or(result) { refuse_publish(result.errors.to_sentence) } unless result.ok?

      redirect_to editor_path, status: :see_other, notice: published_notice(before)
    end

    def discard
      return if refuse_discard_under_hold(@record, to: editor_path)

      result = ::Publishing::DiscardChanges.call(@record, shown_pending: shown_pending)
      return redirect_to editor_path, status: :see_other, notice: [ t("#{SCOPE}.discarded"), result.notice ].compact.join(". ") if result.ok?

      forbidden_or(result) { redirect_to editor_path, status: :see_other, alert: result.errors.to_sentence }
    end

    # Withdraws the change that waits for its time. It writes no row an
    # editor holds, so it asks no hold either.
    def cancel_scheduled_change
      result = ::Publishing::CancelScheduledChange.call(@record, shown_pending: shown_pending)
      return redirect_to editor_path, status: :see_other, notice: t("#{SCOPE}.cancelled") if result.ok?

      forbidden_or(result) { redirect_to editor_path, status: :see_other, alert: result.errors.to_sentence }
    end

    private

    def set_record
      @record = record_of_kind(params[:kind], params[:id])
    end

    def kind = @record.is_a?(Page) ? "page" : "post"

    # The pending copy the dialog showed when the press was made (its id, nil
    # for none): each dialog's form carries it in `pending`, filled from the
    # answer it got when it opened, and the service refuses when it is no
    # longer so (`Publishing::ShownSchedule`). A request without the field (a
    # script) showed nothing and is not checked.
    def shown_pending
      params.key?(:pending) ? params[:pending].presence&.to_i : ::Publishing::ShownSchedule::NOT_ASKED
    end

    def editor_path
      @record.is_a?(Page) ? admin_page_path(@record, **admin_url_options) : admin_post_path(@record, **admin_url_options)
    end

    # `when=at` reads the date field as the Schedule dialog's is read
    # (`Admin::Scheduling#requested_schedule`: the site's time zone, not in
    # the past); `now` is now; `kept` is the time the changes are scheduled
    # for, and is refused when nothing is scheduled any more (another tab
    # cancelled it, or its time came, after this dialog was drawn): the
    # person chose a time, and publishing at once instead would not be what
    # they pressed. No parameter leaves the time to the service (a script).
    def requested_time
      case params[:when]
      when "at" then requested_schedule
      when "now" then [ Time.current, nil ]
      when "kept" then ::Publishing.pending(@record) ? [ nil, nil ] : [ nil, t("#{SCOPE}.not_scheduled") ]
      else [ nil, nil ]
      end
    end

    # Back to the editor, where the dialog reopens with the sentence (and the
    # time that was typed). A draft has no such dialog: a toast.
    def refuse_publish(message)
      return redirect_to editor_path, status: :see_other, alert: message if @record.published_at.nil?

      flash[:publish_error] = message
      flash[:publish_when] = params[:when].to_s.first(8)
      flash[:publish_value] = params[:published_at].to_s.first(40)
      redirect_to editor_path, status: :see_other
    end

    # Says which of three things happened: the rows and the newest copy were
    # the same and no copy was taken (the result does not say, so the
    # baseline's number before and after does), a copy is in force, or one
    # waits for its time.
    def published_notice(before)
      newest = ::Publishing.baseline(@record)
      return t("#{SCOPE}.nothing") if newest&.number == before
      return t("#{SCOPE}.published") unless newest.live_at.future?

      t("#{SCOPE}.scheduled", time: I18n.l(newest.live_at.in_time_zone(Current.site.effective_time_zone), format: :"admin.datetime"))
    end
  end
end
