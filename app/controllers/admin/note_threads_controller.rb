module Admin
  # One thread of a record's notes, always looked up among the container's
  # threads. `show` is the thread view of the notes frame; opening a thread
  # is what marks the viewer's deliveries of it read (notes spec §3.3) --
  # through the service, as every write is. `create` starts one, and `change`
  # is its six buttons. `index` is the record's open threads as JSON, for the
  # mind graph's card, which also starts a note through `create` in JSON.
  #
  # Every write answers the frame: a 303 to the view the person should now
  # see, or the same view again with its status (403, 422), the reason, and
  # what was typed. A thread that is gone is the list with a sentence
  # (`NoteContainer#gone!`), never a 404 inside the drawer.
  class NoteThreadsController < BaseController
    include NoteContainer

    # The route's `change` segment, and what it asks for. Follow and unfollow
    # are two segments, each with its literal: `Notes::SetFollowing` reads any
    # truthy value as "follow", and a form's "false" or "0" is a truthy
    # string, so nothing a request can send is handed to it.
    CHANGES = {
      "resolve" => ->(thread) { Notes::Resolve.call(thread) },
      "reopen" => ->(thread) { Notes::Reopen.call(thread) },
      "pin" => ->(thread) { Notes::Pin.call(thread) },
      "unpin" => ->(thread) { Notes::Unpin.call(thread) },
      "follow" => ->(thread) { Notes::SetFollowing.call(thread, following: true) },
      "unfollow" => ->(thread) { Notes::SetFollowing.call(thread, following: false) }
    }.freeze

    # How much of a thread's first message the mind graph's card is sent.
    EXCERPT = 140

    # The record's open threads as data, for the mind graph's card (notes
    # spec §4.4), which is built in the browser with `textContent` only: text
    # and numbers, no markup. A mention reads as "@Name"; `author` is null
    # for a user who is gone, and the card words that.
    #
    # Its own endpoint, not the frame's: the container was found through the
    # read scope first (`set_container`), so a post outside the viewer's
    # scope, a trashed one and an id that names nothing are the same bare
    # 404, and nothing here redirects to the list. A GET that writes
    # nothing: listing the threads marks no delivery read (opening one does,
    # `show`).
    def index
      listing = Notes::Listing.new(@container, viewer: Current.user)
      threads = listing.pinned + listing.groups.flat_map(&:threads)
      render json: {
        open: listing.open_count,
        threads: threads.map do |thread|
          first = thread.messages.first
          { id: thread.id, text: Notes::Mentions.display(first.body, listing.users).first.truncate(EXCERPT),
            author: listing.users[first.author_id]&.then { |user| Notes.name_of(user) }, replies: thread.messages.size - 1, pinned: thread.pinned,
            # What turns the row's dot accent in the card (spec §4.5): one
            # query for the whole listing (`Notes::Listing#unread?`).
            unread: listing.unread?(thread, Current.user),
            # The viewer's own avatar is the filled one, as in the drawer
            # (`Admin::NotesScreen::AvatarComponent`).
            mine: first.author_id.present? && first.author_id == Current.user&.id }
        end
      }
    end

    # A thread that is not among the container's -- deleted since the link
    # to it was made (an inbox row, `?thread=` on an editor or on the media
    # panel), its block deleted, or a thread of another record -- is not a
    # 404: this GET is the `src` of a lazy frame, where a 404 is "Content
    # missing" and an error in the console. It is the list with "This note is
    # gone", the answer the writes give (`gone!`). That goes for a thread
    # removed between the lookup and the render too (`render_thread` raises
    # then). Only the thread's absence is forgiven: the container was found
    # first (`set_container`), so a record outside the read scope is still
    # the 404, and an image without `media.upload` the 403, before any of
    # this runs.
    def show
      thread = container_threads.find_by(id: params[:id]) or return gone!
      mark_read(thread)
      render_thread(thread, asked: asked)
    rescue ActiveRecord::RecordNotFound
      gone!
    end

    # A new thread on the record, or on one of its blocks (`subject`, a key).
    # A key that names nothing of this record means the record itself: the
    # form only ever sends keys the frame drew.
    def create
      subject = Notes::Listing.new(@container, viewer: Current.user).subject_by_key(params[:subject]) || @container
      result = Notes::Start.call(subject, body: note_body, files: note_files, quote: params[:quote].to_s, origin_view: note_view, origin_locale: admin_locale)
      # The mind graph's card asks in JSON and is answered in kind: the new
      # thread's id, or the reasons (403, 422). It reads the list again
      # itself (`index`), so nothing of the thread is sent back.
      if request.format.json?
        return render(json: { id: result.record.id }, status: :created) if result.ok?

        return render(json: { errors: result.errors }, status: failure_status(result))
      end

      if result.ok?
        redirect_to thread_path(result.record), status: :see_other
      else
        render_list(status: failure_status(result), failed: failed_form("new", result, subject: params[:subject].to_s, quote: params[:quote].to_s))
      end
    end

    def change
      thread = container_threads.find_by(id: params[:id]) or return gone!
      result = CHANGES.fetch(params[:change]).call(thread)

      if result.ok?
        redirect_to thread_path(thread), status: :see_other
      else
        # `form`: which of the thread's buttons was refused, so the sentence
        # is drawn where that button stands (`ThreadComponent`).
        answer_thread_failure(thread, result, key: "thread-#{thread.id}", body: "", form: params[:change])
      end
    end

    private

    # `?edit=<message id>` and `?delete=<message id>`: what a message's "⋯"
    # menu asks for, the thread again with that message's edit form, or its
    # "Delete this note?", in place. Whether the viewer may is the
    # component's question (`Admin::NotesScreen::MessageComponent`), and the
    # service's when the form is sent; an id that names nothing draws nothing.
    #
    # `?shown=<message id>`: the message a reaction was just given to
    # (`Admin::NoteReactionsController`). It asks for nothing but that the
    # message be on screen: the fold it may sit in is drawn open.
    def asked = { edit: params[:edit].to_s.to_i, delete: params[:delete].to_s.to_i, shown: params[:shown].to_s.to_i }

    # `Notes::MarkRead` on a thread takes the container's row lock (`FOR
    # UPDATE` on the page, post or image) before it writes, like every notes
    # write. A thread is opened far more often than it holds something unread
    # for the person opening it, and a GET that locked the page's row every
    # time would queue behind every save of that page for nothing. So the
    # service runs only when there is a row to mark: one indexed EXISTS
    # first, and without an unread delivery no lock and no write at all.
    #
    # Its answer is not read. A refusal or "This note is gone" (the record
    # was trashed or purged since the lookup above) changes nothing about
    # what this request shows: the container was found through the read
    # scope a moment ago, and `render_thread` looks the thread up again among
    # the container's; when it is no longer there, `show` answers the list.
    #
    # A GET THAT WRITES. Opening a thread is what reads it (spec §3.3), so
    # this GET changes rows -- the viewer's own read marks and nothing else,
    # and doing it twice changes nothing more. What it must not be is fetched
    # by anything but a person opening the thread: every link to it carries
    # `data-turbo-prefetch="false"` (`Admin::NotesScreen::ThreadRowComponent`,
    # and the "⋯" menu's Edit and Delete in `MessageComponent`), or Turbo's
    # hover prefetch would mark a row read that nobody opened. A new link to
    # this action needs the same attribute.
    def mark_read(thread)
      return unless Notes::Delivery.unread_on?(thread, Current.user)

      Notes::MarkRead.call(thread: thread)
    end
  end
end
