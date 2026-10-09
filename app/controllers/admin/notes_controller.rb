module Admin
  # One record's notes (notes spec §4.2): the list view of the frame the
  # drawer and the media panel embed, and its parts. Reading the list marks
  # nothing read: a row says "new" until its thread is opened.
  class NotesController < BaseController
    include NoteContainer

    NOTICES = %w[gone].freeze

    def index
      render_list(notice: (params[:notice] if NOTICES.include?(params[:notice])))
    end

    def resolved
      @listing = Notes::Listing.new(@container, limit: params[:limit], viewer: Current.user, locale: admin_locale)
      render :resolved, layout: false
    end

    def counts
      render json: Notes::Counts.for_container(@container, user: Current.user)
    end
  end
end
