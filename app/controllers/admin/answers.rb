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
    # The stream builder an answer is drawn with, over the view its
    # components render in: the one way a responder makes one.
    def self.stream_builder(view) = Turbo::Streams::TagBuilder.new(view)
  end
end
