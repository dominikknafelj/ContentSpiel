module Blocks
  # A public component's contract: what a component a theme may replace
  # promises a visitor, declared once on its class and read by
  # test/values/theme/component_contract_test.rb alone. It is the common
  # declaration (`ComponentContract`: accessibility, motion, content edges,
  # widths, interface, limits) and one keyword of its own:
  #
  # - `words:` the `public.*` keys its own Ruby and its default template read
  #   (`string`, `fixed_word`, `site_string`, `PublicStrings.read`,
  #   `Forms::PublicField#word` and `#error_text`),
  #   a read with an interpolated key as its prefix and `*`
  #   (`public.blocks.note.kinds.*`). `[]` for one that reads none.
  #
  # Its `interface:` is its line in the theme contract
  # (`Theme::Contract.components`), the methods its template may call, and
  # the test holds the two equal: the declaration restates the line, it never
  # widens it. A block's tokens are not declared here: they are the block
  # type's (`t.tokens`) and its stylesheet's, which no one file of the
  # component shows.
  #
  # The `Posts::` components include it too, and a gem's component may. It
  # adds the class method `contract` and nothing else: nothing a template
  # sees or calls changes. It shares only the common declaration with
  # `Admin::Ui::Contract`, CS Studio's, and a class includes one or the other.
  module Contract
    PUBLIC = %i[words].freeze
    WORD = /\Apublic(\.[a-z_]+)+(\.\*)?\z/

    Declaration = Data.define(*ComponentContract::COMMON, *PUBLIC)

    def self.included(base)
      raise ArgumentError, "#{base.name} includes both contracts: a class includes one" if base.include?(Admin::Ui::Contract)

      base.include(ComponentContract)
      base.extend(ClassMethods)
    end

    module ClassMethods
      private

      def contract_declaration(declared)
        words = declared[:words]
        unless words.nil? || words.is_a?(Array) && words.all? { |word| word.is_a?(String) && WORD.match?(word) }
          ComponentContract.refuse(self, :words, "is a list of public.* keys, a prefix ending in .*")
        end

        ComponentContract.declare(self, Declaration, declared)
      end
    end
  end
end
