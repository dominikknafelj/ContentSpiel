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
