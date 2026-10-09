module Admin
  # The signed-in person's notes inbox (notes spec §5). Open to every
  # signed-in user, like the dashboard: what it lists is narrowed by the read
  # scope inside the queries (`Dashboard::NotesForYou`, `Dashboard::OpenThreads`),
  # so someone with no rights gets empty lists, and a record that left the
  # viewer's scope or went to the trash is simply not there.
  #
  # Five answers: the full list, "Mark all read", and the three parts a page
  # shows of the inbox, each fetched again on its own -- the two dashboard
  # cards as their frames, and the sidebar's number as JSON. None of the
  # three renders the layout, so none pays for the sidebar.
  #
  # Nothing here marks one row read: a row is read by opening its thread
  # (`Admin::NoteThreadsController#show`), which is where its link leads.
  class NoteInboxController < BaseController
    PER_PAGE = 50

    def index
      @inbox = inbox
      @pagination = Pagination.new(page: params[:page], per_page: PER_PAGE, total: @inbox.total)
      @rows = @pagination.out_of_range? ? [] : @inbox.rows(limit: PER_PAGE, offset: @pagination.offset)
    end

    # Every unread delivery of the actor's, the ones hidden at this moment
    # included (`Notes::MarkRead`). Back to where the button was pressed: the
    # dashboard's card says `back=dashboard`, anything else is the full list.
    def read
      Notes::MarkRead.call
      back = params[:back] == "dashboard" ? admin_root_path(**admin_url_options) : admin_notes_path(**admin_url_options)
      redirect_to back, status: :see_other
    end

    def card
      render partial: "admin/note_inbox/card", locals: { rows: inbox.rows, unread: inbox.unread_count }
    end

    def open_threads
      render partial: "admin/note_inbox/open_threads", locals: { open_threads: Dashboard::OpenThreads.new(actor: Current.actor) }
    end

    def unread
      render json: { unread: inbox.unread_count }
    end

    private

    def inbox = @inbox ||= Dashboard::NotesForYou.new(actor: Current.actor, locale: admin_locale)
  end
end
