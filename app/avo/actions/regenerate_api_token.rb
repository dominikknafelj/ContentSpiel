# Standalone (no record selection needed) rather than an action on an
# existing ApiToken row: the previous v1 design had no way to mint the
# *first* token at all (Avo::Resources::ApiToken's Create button is
# deliberately closed off -- see that resource's own comment), so this has
# to work whether or not one already exists. Scoped to `current_user` (the
# admin running it in Avo), not an arbitrary user field, so one admin can't
# mint a token that authenticates as a different one.
class Avo::Actions::RegenerateApiToken < Avo::BaseAction
  self.name = "Regenerate my API token"
  self.standalone = true
  self.message = "This revokes your current API token (if any) and creates a new one. " \
    "The old token stops working immediately, and the new one is shown once -- copy it before closing this."

  def handle(current_user:, **args)
    _token, raw = ApiTokens::Issue.call(current_user, rotate: true).record

    succeed("New token: #{raw}")
  end
end
