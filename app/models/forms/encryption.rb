module Forms
  # Whether this site has Active Record encryption keys: without them a form keeps nothing and takes no answers,
  # because a submission is stored encrypted and nothing else may hold the
  # answers (no sealed copy in a job, no plain row). The Forms screen and
  # System status say so; `Forms::Save` refuses keeping, `Forms::Form#keeps?`
  # is false.
  #
  # Asked of the key provider, the thing that raises
  # `ActiveRecord::Encryption::Errors::Configuration` ("Missing Active Record
  # encryption credential") at the first encryption on a site without keys:
  # nothing is encrypted or decrypted to find out.
  #
  # Memoised for the life of the process outside test: keys come from the
  # environment or the credentials, read at boot, and a change of them is a
  # restart. In test it is asked every time, so `without_encryption_keys`
  # (test/support/encryption_keys.rb) is seen inside its block and not after.
  module Encryption
    module_function

    def available?
      return probe if Rails.env.test?

      @available = probe if @available.nil?
      @available
    end

    def probe
      ActiveRecord::Encryption.key_provider.encryption_key
      true
    rescue ActiveRecord::Encryption::Errors::Configuration
      false
    end
  end
end
