module Admin
  module Answers
    # What a responder hands back: the `<turbo-stream>` tags in the order the
    # browser applies them, and the Rack status they are sent with. The
    # controller renders it as it is (`render turbo_stream: streams, status:`).
    Answer = Data.define(:streams, :status)
  end
end
