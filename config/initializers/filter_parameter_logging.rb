# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # An API token's SHA-256 lookup digest (`api_tokens.lookup_digest`): the exact name, not a bare
  # :digest, which would also hide harmless digests. The :token entry no longer matches it.
  :lookup_digest
]

# A note's text (notes spec, decision D14: it reaches no log). The notes forms
# send it as `body` and `quote`, top-level names that say nothing by
# themselves -- and a bare `:body` here would be wrong twice over: posts and
# blocks have a `body` of their own, and `Audit::Snapshot.scrub` drops every
# snapshot key this list matches, so their audit snapshots would lose it. So
# the two names are filtered BY WHERE THEY ARRIVE: in a request to one of the
# notes controllers (`admin/notes`, `admin/note_threads`,
# `admin/note_messages`, ...), which is what the third argument holds. A
# snapshot's keys are asked with no request around them and with `true` for a
# value, and are never touched. `mention_names` is the composer's own field:
# display names, which for a user without a name are email addresses.
#
# The first line of a request's log ("Started GET ...") is another matter: it
# filters each pair of the query string on its own, with nothing to say which
# controller it is for, so the lambda can't reach it. The one piece of text a
# notes GET carries is the passage a new note quotes, and its name in a URL is
# therefore `note_quote`, a bare entry here. It collides with no model
# attribute (a thread's column is `quote`), so no audit snapshot changes.
Rails.application.config.filter_parameters += [
  :mention_names, :note_quote,
  lambda do |key, value, params = nil|
    next unless value.is_a?(String) && %w[body quote].include?(key.to_s)
    next unless params.is_a?(Hash) && params["controller"].to_s.start_with?("admin/note")

    value.replace("[FILTERED]")
  end
]
