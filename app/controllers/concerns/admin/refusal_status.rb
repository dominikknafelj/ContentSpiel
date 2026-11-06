module Admin
  # The one rule for the HTTP status of a write a service refused: 403 for a
  # permission refusal (`result.denied?`: access-control design spec §3.4, a
  # forged or stale-tab request by someone who may only read), 422 for
  # anything else. Every refusal in CS Studio is answered through it: the
  # autosave forms (`AutosaveResponses#autosave_status`), the block answers
  # (`Admin::Answers::BlockRefused`), the notes (`NoteContainer`), and the
  # media and tag screens.
  module RefusalStatus
    def self.for(result) = result.denied? ? :forbidden : :unprocessable_entity
  end
end
