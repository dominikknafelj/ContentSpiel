module Admin
  module SettingsScreen
    # The Sign-in card, after Mail, for an owner alone (`SettingsSections`'
    # `owner_only`; `Settings::Save` refuses the field to anyone else): who
    # must sign in with a passkey (`SiteSetting::PASSKEY_POLICIES`), as the
    # shared segmented control's radios, a field of the one Settings form
    # saved with its save bar.
    #
    # - `policy` is the choice shown checked: what was typed after a refused
    #   save, else the stored policy, or the environment's default while none
    #   is stored (`SiteSetting#effective_passkey_policy`).
    # - `uncovered` is how many people the SAVED policy covers who hold no
    #   passkey (`SignIn::Passkeys::Policy#uncovered_count`), said in a line under the
    #   choice; at `nobody` (read from `site`, the saved row) there is no line,
    #   since nobody is covered.
    # - `changed` is the wrapper's `data-save-bar-changed` ("saved" when a
    #   refused save left the choice unsaved).
    #
    # The policy takes effect at each covered person's next sign-in, so the
    # count stays what it was until then.
    class SignInCardComponent < Admin::AdminComponent
      FIELD_ID = "settings-passkey_policy".freeze

      def initialize(site:, policy:, uncovered:, changed: nil)
        @site = site
        @policy = policy
        @uncovered = uncovered
        @changed = changed
      end

      private

      attr_reader :site, :policy, :uncovered, :changed

      def segments
        SiteSetting::PASSKEY_POLICIES.map do |name|
          { label: t(".policies.#{name}"), value: name, id: "#{FIELD_ID}-#{name}", current: name == policy }
        end
      end

      def count_line?
        site.effective_passkey_policy != "nobody"
      end

      def count_line = uncovered.positive? ? t(".uncovered", count: uncovered) : t(".all_covered")
    end
  end
end
