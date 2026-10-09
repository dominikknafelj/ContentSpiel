module Admin
  # The signed-in person's notes inbox (notes spec §5). Open to every
  # signed-in user, like the dashboard: what it lists is narrowed by the read
  # scope inside the queries (`Dashboard::NotesForYou`, `Dashboard::OpenThreads`),
  # so someone with no rights gets empty lists, and a record that left the
  # viewer's scope or went to the trash is simply not there.
  #
  # Six answers: the full list, "Mark all read", the three parts a page
  # shows of the inbox, each fetched again on its own -- the two dashboard
  # cards as their frames, and the sidebar's number as JSON -- and one
  # delivery as data, for the toast. None of the last four renders the
  # layout, so none pays for the sidebar.
  #
  # Nothing here marks one row read: a row is read by opening its thread
  # (`Admin::NoteThreadsController#show`), which is where its link leads.
  class NoteInboxController < BaseController
    PER_PAGE = 50

    # Which tab this is (`X-Notes-Tab`, as `Admin::NoteContainer#note_tab`
    # reads it for a record's notes): "Mark all read" is a notes write too,
    # and its signal (`Notes::Signals.inbox`) names the tab that pressed it,
    # whose page the redirect draws again anyway. Checked for shape and used
    # for nothing but being echoed.
    before_action { Current.notes_tab = request.headers["X-Notes-Tab"].to_s[Notes::Signals::TAB] }

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

    # One of the viewer's own deliveries as data (notes spec §6.1, §6.4): what
    # a tab asks for after a signal named its id, for the toast and the
    # desktop notification. THE SIGNAL SAID NOTHING, and may have reached
    # someone who has since lost the right to read the record: this is where
    # that is decided, through `Dashboard::NotesForYou#find` -- the viewer's
    # own row on a record they may read now, or not found, and not found says
    # nothing about which.
    #
    # The sentence is the inbox row's, from the same keys
    # (`Admin::NotesScreen::InboxRowComponent#sentence`), as TEXT: `I18n.t`,
    # not the view's `t`, which would escape the name for a page -- the
    # script writes it with `textContent`. A GET that writes nothing: only
    # opening the thread reads a delivery.
    def delivery
      row = inbox.find(params[:id]) or raise ActiveRecord::RecordNotFound

      render json: { id: row.id, reason: row.reason, sentence: delivery_sentence(row), title: row.title || t("admin.components.notes_screen.inbox_row.untitled"),
        excerpt: row.excerpt, url: helpers.note_route_path(row.route, **admin_url_options), thread_id: row.thread_id }
    end

    private

    # A named person, one who is gone, or nobody (a reopen names nobody, and
    # neither does a note whose author was deleted): the row component's
    # three cases.
    def delivery_sentence(row)
      scope = "admin.components.notes_screen.inbox_row.#{row.reason}"
      return I18n.t("#{scope}.nobody") unless row.by || row.by_id
      return I18n.t("#{scope}.deleted") unless row.by

      I18n.t("#{scope}.somebody_html", name: row.by.display_name)
    end

    def inbox = @inbox ||= Dashboard::NotesForYou.new(actor: Current.actor, locale: admin_locale)
  end
end
