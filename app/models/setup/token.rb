# The one-time code /setup asks for before anyone can create the first admin
# (design spec 2026-09-26 §3), so a publicly reachable fresh install can't be
# claimed by whoever finds it first. Derived from secret_key_base rather than
# stored: identical across restarts and Puma workers with nothing to persist,
# and anyone holding secret_key_base already owns the app.
module Setup
  module Token
    PURPOSE = "contentspiel setup token"

    def self.value
      ENV["SETUP_TOKEN"].presence ||
        Rails.application.key_generator.generate_key(PURPOSE, 12).unpack1("H*")
    end

    def self.valid?(candidate)
      ActiveSupport::SecurityUtils.secure_compare(candidate.to_s.strip, value)
    end
  end
end
