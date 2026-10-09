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
  # WHAT IS SENT. The type is the one STORED, which `Notes::Files` read from
  # the bytes when the file came -- nothing in the request names a type or a
  # disposition -- and a stored type that is not on the allowed list (a row
  # written around `Notes::Files`) is `application/octet-stream`. Only the
  # four image types are answered inline (the thread shows them in an
  # `<img>`, and a click opens the same address in a new tab); anything else
  # is a download. No variant is made. Every answer carries three guards
  # (`GUARDS`): `nosniff`, so the type sent is the type used; a `sandbox`
  # content security policy, so a file that a browser did open as a document
  # runs nothing and has no origin; and `same-origin` as its resource
  # policy, so no other site can embed it.
  #
  # ITS NAME IS IN NO LOG LINE (decision D14). `send_data` given a
  # `filename:` makes Rails log "Sent data <name>" at INFO, production's
  # level, on every view and download. So the `Content-Disposition` header is
  # built here (Rails' own formatter: an ASCII `filename=` and an RFC 5987
  # `filename*=`, from the sanitised name) and `send_data` is told neither a
  # name nor a disposition.
  #
  # CACHING. A document is `private, no-store`: no cache keeps a copy. A
  # picture is `no-cache, private` with an ETag: the reader's own browser
  # may keep it and must ASK before every use, so it is not downloaded again
  # each time a thread is opened, and never used without this action having
  # run -- the 304 is answered here, at the end of the same lookup, so
  # someone who lost the right to the record gets the 404 (or 403) of a full
  # request, never "not modified". The ETag is of the blob's id and
  # checksum; a note's file never changes.
  class NoteFilesController < BaseController
    include NoteContainer

    GUARDS = { "X-Content-Type-Options" => "nosniff", "Content-Security-Policy" => "sandbox", "Cross-Origin-Resource-Policy" => "same-origin" }.freeze # i18n-ok: HTTP headers and their values, not copy

    def show
      thread = container_threads.find(params[:thread_id])
      message = thread.messages.find(params[:message_id])
      blob = message.files_attachments.find(params[:id]).blob
      allowed = Notes::Files::ALLOWED.key?(blob.content_type)
      image = allowed && Notes::Files.image?(blob.content_type)

      response.headers.merge!(GUARDS)
      # Through Rails' own cache-control hash: it writes the header last, and
      # for `no-cache` keeps `private` only as an extra directive.
      response.cache_control.replace(image ? { no_cache: true, extras: [ "private" ] } : { no_store: true, private: true })
      return unless !image || stale?(strong_etag: [ blob.id, blob.checksum ], template: false)

      disposition = ActionDispatch::Http::ContentDisposition.format(disposition: image ? "inline" : "attachment", filename: blob.filename.sanitized)
      response.headers["Content-Disposition"] = disposition # i18n-ok: an HTTP header's name, not copy
      send_data blob.download, type: allowed ? blob.content_type : "application/octet-stream", disposition: nil
    rescue ActiveStorage::FileNotFoundError
      # The row is there and the bytes are not (a storage that failed after
      # the note was committed): not found, like any file that is not there.
      head :not_found, content_type: "text/plain"
    end
  end
end
