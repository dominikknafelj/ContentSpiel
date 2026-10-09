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
    # refused or failed write on that thread answers.
    def render_thread(thread, status: :ok, failed: nil)
      @listing = Notes::Listing.new(@container, viewer: Current.user)
      @thread = @listing.find(thread.id) or raise ActiveRecord::RecordNotFound
      @failed = failed
      render "admin/notes/thread", status: status, layout: turbo_frame_request? ? false : "admin"
    end
  end
end
