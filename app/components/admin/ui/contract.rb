module Admin
  module Ui
    # A shared CS Studio component's contract: the common declaration
    # (`ComponentContract`) and what a shared component adds to it, held to
    # the code by `test/support/ui_contract.rb`.
    #
    # - `states:` the states a static render draws, each but the pointer and
    #   keyboard ones (`STATES_NOT_PREVIEWED`) a preview example of the same
    #   name.
    # - `script_states:` a state only a script reaches (a dialog's `open`), or
    #   one a static render draws invisibly (a tooltip's hidden bubble), mapped
    #   to the `[file, test name]` of the browser test that holds it. A static
    #   render shows nothing of it, so it is never in `states:` and has no
    #   example.
    # - `keys:` the key paths it owns under `admin.components.ui.<name>`, a
    #   plural (`one`, `other`) being one.
    # - `slots:` its ViewComponent slots.
    # - `controller:` the Stimulus identifier it attaches itself
    #   (`data-controller` on its own markup), or nil. A component that is only
    #   a target or an action of a controller someone else attaches declares
    #   nil and says whose in its `limits:`.
    # - `keyboard:` the `[file, test name]` of its keyboard browser test, or
    #   nil for a component made before the contract.
    module Contract
      STATES_NOT_PREVIEWED = %i[hover focus pressed].freeze
      STUDIO = %i[states keys slots controller script_states keyboard].freeze
      DEFAULTS = { script_states: {}, keyboard: nil }.freeze

      Declaration = Data.define(*ComponentContract::COMMON, *STUDIO)

      def self.included(base)
        raise ArgumentError, "#{base.name} includes both contracts: a class includes one" if base.include?(Blocks::Contract)

        base.include(ComponentContract)
        base.extend(ClassMethods)
      end

      module ClassMethods
        private

        def contract_declaration(declared)
          values = DEFAULTS.merge(declared)
          symbols = ->(value) { value.is_a?(Array) && value.all?(Symbol) }
          test_ref = ->(value) { value.is_a?(Array) && value.size == 2 && value.all? { |part| part.is_a?(String) && part.present? } }

          refuse_contract(:states, "is a list of Symbols") unless symbols.(values[:states])
          refuse_contract(:keys, "is a list of key paths") unless values[:keys].is_a?(Array) && values[:keys].all? { |key| key.is_a?(String) && key.present? }
          refuse_contract(:slots, "is a list of Symbols") unless symbols.(values[:slots])
          refuse_contract(:controller, "is a Stimulus identifier or nil") unless values[:controller].nil? || values[:controller].is_a?(String) && values[:controller].present?
          script_states = values[:script_states]
          unless script_states.is_a?(Hash) && script_states.all? { |state, test| state.is_a?(Symbol) && test_ref.(test) }
            refuse_contract(:script_states, "maps a state to the [file, test name] of its browser test")
          end
          both = Array(values[:states]) & script_states.keys
          refuse_contract(:script_states, "names #{both.join(', ')}, which states: names too: a state is drawn statically or held by a script, not both") if both.any?
          refuse_contract(:keyboard, "is the [file, test name] of a browser test, or nil") unless values[:keyboard].nil? || test_ref.(values[:keyboard])

          ComponentContract.declare(self, Declaration, declared, defaults: DEFAULTS)
        end

        def refuse_contract(keyword, rule) = ComponentContract.refuse(self, keyword, rule)
      end
    end
  end
end
