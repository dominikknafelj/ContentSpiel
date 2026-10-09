module Admin
  # What every notes controller shares: the container, found THROUGH THE READ
  # SCOPE before anything else is looked at (notes spec §3.4). A page or post
  # outside the viewer's scope, a trashed one and an id that names nothing are
  # the same 404; the media library has no per-image right, so its gate is
  # the module's own (`media.upload`, a 403 like `Admin::MediaController`'s).
  # A thread, a message or a file is then looked up among `container_threads`
  # only.
  #
  # The notes frame has two views under one id, `turbo-frame#notes`: the list
  # (`render_list`) and one thread (`render_thread`), which replaces it.
  module NoteContainer
    extend ActiveSupport::Concern

    included do
      before_action :set_container
      # The three notes views ask which surface they are drawn for.
      helper_method :note_view
    end

    private

    def set_container
      @container =
        case params[:container_type]
        when "page" then admin_scope(Page.all).find(params[:container_id])
        when "post" then admin_scope(Post.all).find(params[:container_id])
        else
          return forbidden! unless can?("media.upload")

          Media::Asset.kept.find(params[:container_id])
        end
    end

    def container_threads = Notes::Thread.where(container: @container)

    # Which surface the frame is drawn on; it travels in every notes URL so
    # an answer is drawn for the same surface, and a new thread records it.
    def note_view = Notes::Thread::ORIGIN_VIEWS.include?(params[:view].to_s) ? params[:view].to_s : "editor"

    def note_frame_params(**extra) = { view: (note_view unless note_view == "editor"), **admin_url_options, **extra }.compact

    def notes_path(**extra) = admin_record_notes_path(params[:container_type], @container.id, **note_frame_params(**extra))

    def thread_path(thread, **extra) = admin_record_note_thread_path(params[:container_type], @container.id, thread, **note_frame_params(**extra))

    # The list: what `index` answers, and what a refused or failed new note
    # answers with its own status, the typed text kept (`failed`).
    def render_list(status: :ok, failed: nil, notice: nil)
      @listing = Notes::Listing.new(@container, limit: params[:limit], viewer: Current.user)
      @failed = failed
      @notice = notice
      render "admin/notes/index", status: status, layout: turbo_frame_request? ? false : "admin"
    end

    # One thread, in the list's place: what `show` answers, and what a
    # refused or failed write on that thread answers. `asked` names the one
    # message whose edit form or delete question the view draws
    # (`Admin::NoteThreadsController#asked`).
    def render_thread(thread, status: :ok, failed: nil, asked: {})
      @listing = Notes::Listing.new(@container, viewer: Current.user)
      @thread = @listing.find(thread.id) or raise ActiveRecord::RecordNotFound
      @failed = failed
      @asked = asked
      render "admin/notes/thread", status: status, layout: turbo_frame_request? ? false : "admin"
    end

    # --- writing (the forms of the frame) ------------------------------------

    # How many names of the picker's map are read. A message may mention 20
    # people (`Notes::Mentions::MAX`); the map can hold a few more, for names
    # picked and then deleted from the text again.
    MAX_MENTION_NAMES = 50

    # The typed body with the names the picker inserted turned into tokens
    # (`Notes::Mentions.tokenize`). `mention_names` comes from the browser and
    # is used for nothing else: whom a note may mention is the service's check
    # on the ids that result.
    def note_body = Notes::Mentions.tokenize(params[:body].to_s, mention_names)

    # `{ "Dana Smith" => 7 }`, from the form's JSON. Anything that is not a
    # name with an id is left out, so what a failed form is drawn with again
    # is that shape and nothing else.
    def mention_names
      names = JSON.parse(params[:mention_names].to_s)
      return {} unless names.is_a?(Hash)

      names.first(MAX_MENTION_NAMES).select { |name, id| name.present? && id.to_s.match?(/\A\d{1,18}\z/) }.to_h
    rescue JSON::ParserError
      {}
    end

    def failure_status(result) = result.denied? ? :forbidden : :unprocessable_entity

    # What a failed form gets back: its own key, what was typed, and why.
    # Nothing here reads `result.record`: a notes service's failure has none
    # ("This note is gone" for a record trashed or a thread removed a moment
    # ago is a failure like any other).
    def failed_form(key, result, **extra)
      { key: key, body: params[:body].to_s, names: mention_names, errors: result.errors, **extra }
    end

    # The thread (or what it was on) is no longer there: back to the list,
    # which says so. Never a 404 inside the drawer.
    def gone! = redirect_to(notes_path(notice: "gone"), status: :see_other)

    # A refused or failed write on a thread (Review Focus 3). The thread is
    # looked up again first: when the failure is that it went a moment ago
    # (its block deleted, its last message deleted in another tab), there is
    # no thread view left to draw the sentence in, and the list says it.
    # Otherwise the thread again, with the reason in the form `key` names.
    def answer_thread_failure(thread, result, key:, **extra)
      return gone! unless container_threads.exists?(id: thread.id)

      render_thread(thread, status: failure_status(result), failed: failed_form(key, result, **extra))
    end
  end
end
