module Admin
  # A note's file (notes spec D15, §3.6): the ONLY way one is read. Active
  # Storage's own read URLs are public to whoever holds one and do not expire
  # (`config/initializers/active_storage_access.rb`); a note's file may be
  # confidential, so no such URL is ever written into a page, and the bytes
  # are sent from here, after the same lookup as every notes request.
  #
  # THE LOOKUP IS A CHAIN, and each step is asked only of what the step before
  # found: the container through the read scope (`NoteContainer#set_container`:
  # a page or post outside the viewer's scope, a trashed one and an id that
  # names nothing are the same 404; an image without `media.upload` the 403
  # it is everywhere), then the thread among the container's, the message
  # among the thread's, the attachment among the message's files. So the id
  # is an ATTACHMENT's and nothing else -- never a blob's key or a signed id
  # -- and it can't be turned into a way to read any other upload: a library
  # image's attachment, a file of another record's note, and a file of
  # another message of the same thread are all not found.
  #
  # WHAT IS SENT. `X-Content-Type-Options: nosniff` always. The type is the
  # one STORED, which `Notes::Files` read from the bytes when the file came
  # -- nothing in the request names a type or a disposition -- and a stored
  # type that is not on the allowed list (a row written around
  # `Notes::Files`) is `application/octet-stream`. Only the four image types
  # are answered inline (the thread shows them in an `<img>`, and a click
  # opens the same address in a new tab); anything else is a download. No
  # variant is made. `private, no-store`: no cache, shared or the browser's
  # own, keeps a copy that would outlast the reader's right to it.
  class NoteFilesController < BaseController
    include NoteContainer

    def show
      thread = container_threads.find(params[:thread_id])
      message = thread.messages.find(params[:message_id])
      blob = message.files_attachments.find(params[:id]).blob
      allowed = Notes::Files::ALLOWED.key?(blob.content_type)

      response.headers["X-Content-Type-Options"] = "nosniff" # i18n-ok: an HTTP header's name and its value, not copy
      response.headers["Cache-Control"] = "private, no-store" # i18n-ok: an HTTP header's name and its directives, not copy
      send_data blob.download, filename: blob.filename.sanitized, type: allowed ? blob.content_type : "application/octet-stream",
        disposition: allowed && Notes::Files.image?(blob.content_type) ? "inline" : "attachment"
    rescue ActiveStorage::FileNotFoundError
      # The row is there and the bytes are not (a storage that failed after
      # the note was committed): not found, like any file that is not there.
      head :not_found, content_type: "text/plain"
    end
  end
end
