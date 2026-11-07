# What a component promises, declared once on its class with `contract(...)`
# and read by the tests alone: nothing at run time asks for it. This is the
# part every component shares, CS Studio's and a visitor's page's alike;
# `Admin::Ui::Contract` builds on it with what a shared CS Studio component
# adds, and a class includes that one, never both.
#
# - `accessibility:` one sentence: the role, the name and the keyboard.
# - `motion:` `:none`, or `:reduced` (it moves, and holds still under
#   `prefers-reduced-motion`).
# - `content_edges:` the edges of content it is drawn for (`EDGES`).
# - `widths:` how it takes its width: from its container, fluid, or fixed
#   (`WIDTHS`).
#
# - `interface:` what a caller hands it or calls on it.
# - `limits:` at least one sentence of what it does not do.
#
# The stylesheets scan a component's file as they scan any source, so no
# word of a declaration may be a Tailwind utility (`from_container`, not
# `container`), or the declaration adds a rule to a stylesheet
# (test/components/component_contract_test.rb).
#
# A declaration it cannot read is refused when the class loads, with the
# keyword and the class named, so a mistyped edge never reaches a test as a
# silent pass.
module ComponentContract
  COMMON = %i[accessibility motion content_edges widths interface limits].freeze
  EDGES = %i[long short none many missing].freeze
  WIDTHS = %i[from_container fluid fixed_width].freeze
  MOTION = %i[none reduced].freeze

  Declaration = Data.define(*COMMON)

  def self.included(base)
    base.extend(ClassMethods)
  end

  # Checks `declared` against `data_class`'s members (`defaults` filling the
  # optional ones), validates the common keywords and answers the frozen
  # declaration. A module built on this one validates its own keywords and
  # hands them here with its own `Data`.
  def self.declare(klass, data_class, declared, defaults: {})
    unknown = declared.keys - data_class.members
    raise ArgumentError, "#{klass.name}'s contract has no keyword #{unknown.join(', ')}" if unknown.any?
    missing = data_class.members - declared.keys - defaults.keys
    raise ArgumentError, "#{klass.name}'s contract is missing #{missing.join(', ')}" if missing.any?

    values = defaults.merge(declared)
    validate_common(klass, values)
    data_class.new(**values.transform_values { |value| deep_freeze(value) }).freeze
  end

  def self.validate_common(klass, values)
    refuse(klass, :accessibility, "is one sentence") unless values[:accessibility].is_a?(String) && values[:accessibility].strip.present?
    refuse(klass, :motion, "is one of #{MOTION.join(', ')}") unless MOTION.include?(values[:motion])
    refuse(klass, :content_edges, "is a list of #{EDGES.join(', ')}") unless symbols?(values[:content_edges]) && (values[:content_edges] - EDGES).empty?
    refuse(klass, :widths, "is one of #{WIDTHS.join(', ')}") unless WIDTHS.include?(values[:widths])
    refuse(klass, :interface, "is a list of Symbols") unless symbols?(values[:interface])
    limits = values[:limits]
    refuse(klass, :limits, "is a list of at least one sentence") unless limits.is_a?(Array) && limits.any? && limits.all? { |limit| limit.is_a?(String) && limit.strip.present? }
  end

  def self.refuse(klass, keyword, rule)
    raise ArgumentError, "#{klass.name}'s contract: #{keyword} #{rule}"
  end

  def self.symbols?(value) = value.is_a?(Array) && value.all?(Symbol)

  def self.deep_freeze(value)
    case value
    when Array then value.map { |item| deep_freeze(item) }.freeze
    when Hash then value.to_h { |key, item| [ key, deep_freeze(item) ] }.freeze
    else value.frozen? ? value : value.dup.freeze
    end
  end

  module ClassMethods
    # With keywords it declares; without, it answers the declaration, or nil
    # for a class that has not declared.
    def contract(**declared)
      return (@contract if defined?(@contract)) if declared.empty?
      raise ArgumentError, "#{name} declares its contract twice" if defined?(@contract)

      @contract = contract_declaration(declared)
    end

    private

    def contract_declaration(declared) = ComponentContract.declare(self, ComponentContract::Declaration, declared)
  end
end
