# Runs a block as a site with no Active Record encryption keys runs: the
# three keys are gone from `ActiveRecord::Encryption.config`, and the key
# provider is built again from that config (`with_encryption_context` with no
# provider), so whatever encrypts in the block raises what production without
# keys raises, `ActiveRecord::Encryption::Errors::Configuration` ("Missing
# Active Record encryption credential"), at the first encryption.
#
#   without_encryption_keys { patch ... }
#
# The context is thread-local and an integration test's request runs on the
# test's thread, so the request sees it too. The keys are put back in an
# `ensure`, also when the block raises.
module EncryptionKeys
  KEYS = %i[primary_key deterministic_key key_derivation_salt].freeze

  def without_encryption_keys(&block)
    config = ActiveRecord::Encryption.config
    were = KEYS.index_with { |name| config.instance_variable_get(:"@#{name}") }
    KEYS.each { |name| config.public_send(:"#{name}=", nil) }
    ActiveRecord::Encryption.with_encryption_context(key_provider: nil, &block)
  ensure
    were&.each { |name, value| config.public_send(:"#{name}=", value) }
  end
end
