module Admin
  # One thread of a record's notes, always looked up among the container's
  # threads. `show` is the thread view of the notes frame; opening a thread
  # is what marks the viewer's deliveries of it read (notes spec §3.3) --
  # through the service, as every write is.
  class NoteThreadsController < BaseController
    include NoteContainer

    def show
      thread = container_threads.find(params[:id])
      mark_read(thread)
      render_thread(thread)
    end

    private

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
    # the container's, answering 404 by itself when it is no longer there.
    #
    # A GET THAT WRITES. Opening a thread is what reads it (spec §3.3), so
    # this GET changes rows -- the viewer's own read marks and nothing else,
    # and doing it twice changes nothing more. What it must not be is fetched
    # by anything but a person opening the thread: every link to it carries
    # `data-turbo-prefetch="false"` (`Admin::NotesScreen::ThreadRowComponent`),
    # or Turbo's hover prefetch would mark a row read that nobody opened. A
    # new link to this action needs the same attribute.
    def mark_read(thread)
      return unless Notes::Delivery.unread_on?(thread, Current.user)

      Notes::MarkRead.call(thread: thread)
    end
  end
end
