# The ways to sign in to CS Studio that a gem adds to the built-in four
# (`Session::METHODS`), registered through the hook
# `ContentSpiel::Plugins.sign_in_methods` and replayed into this registry by
# `config/initializers/sign_in_methods.rb` after `reset!` on every
# `to_prepare` (the reason `StudioModules` gives: a gem's own `to_prepare` runs
# before the application's, and a reload unloads the registry).
#
# Plain data, as the other registries: `path:` is a route helper's NAME on
# `main_app` (the button POSTs to it), `label:` an I18n key of the gem's, and
# nothing here builds a URL or a component.
#
# `recheck:` is optional: an object answering `call(session)` with `:ok`,
# `:revoked` or `:unavailable`, asked once a day of every session the method
# made, as an SSO session's refresh is. A method with none is never asked
# again, so `Session.start` stores neither a check date nor a provider token
# for it.
#
# `passkey_policy:` is `:applies`, or `:exempt` when the method's provider is
# itself the second factor, as SSO's is (`Passkeys::Policy#enrolment_due?`).
module SignIn
  module Methods
    PASSKEY_POLICIES = %i[applies exempt].freeze

    # Built-in and never registered: its provider is the second factor.
    BUILT_IN_EXEMPT = %w[sso].freeze

    Entry = Data.define(:name, :label, :path, :recheck, :passkey_policy)

    @entries = []

    class << self
      # Raises on a name taken and on a policy outside `PASSKEY_POLICIES`.
      def register(name, label:, path:, recheck: nil, passkey_policy: :applies)
        name = name.to_s
        raise ArgumentError, "a sign-in method named #{name.inspect} is registered already" if find(name)
        raise ArgumentError, "#{name.inspect}: passkey_policy is one of #{PASSKEY_POLICIES.join(", ")}, not #{passkey_policy.inspect}" unless PASSKEY_POLICIES.include?(passkey_policy)
        raise ArgumentError, "#{name.inspect}: recheck answers call(session), and #{recheck.inspect} does not" if recheck && !recheck.respond_to?(:call)

        Entry.new(name:, label:, path:, recheck:, passkey_policy:).tap { |entry| @entries << entry }
      end

      # In registration order.
      def entries = @entries.dup

      def find(name) = @entries.find { |entry| entry.name == name.to_s }

      def names = @entries.map(&:name)

      # Whether a person who signed in this way is spared the passkey policy.
      def exempt?(method)
        BUILT_IN_EXEMPT.include?(method.to_s) || find(method)&.passkey_policy == :exempt
      end

      # Whether the method's sessions are asked of their provider again.
      def rechecked?(method) = !find(method)&.recheck.nil?

      # For the initializer: empty, to be filled again.
      def reset! = @entries = []
    end
  end
end
