module Admin
  # The answers a CS Studio write is given, one responder per outcome: what a
  # block's save, add, move, copy or delete draws when it went through
  # (`BlockSaved`), when it was refused (`BlockRefused`) or when the block is
  # gone (`BlockGone`), and the two 409s every autosave form shares (`Stale`,
  # `Held`). A responder decides nothing: the action has looked the record up,
  # claimed it and called the service, and asks the one responder for its
  # outcome. It draws, from a `Context` it is handed, so it is tested without a
  # request.
  #
  # They live under `app/controllers` because they draw views and know the
  # routes: they are the controller layer, which a model, a query or a service
  # never reaches (`test/lib/dependency_direction_test.rb`).
  module Answers
    # What a responder hands back: the `<turbo-stream>` tags in the order the
    # browser applies them, and the Rack status they are sent with. The
    # controller renders it as it is (`render turbo_stream: streams, status:`).
    Answer = Data.define(:streams, :status)
  end
end
