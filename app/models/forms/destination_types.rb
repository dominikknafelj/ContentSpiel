module Forms
  # The registry of destination types (`Forms::DestinationType`). Reset and
  # filled in `config/initializers/types.rb` after the content model's field
  # types (a destination's settings are declared against them), mail built
  # in; a gem's types are replayed after everything else
  # (`ContentSpiel::Plugins.form_destinations`), as block types are.
  #
  #   Forms::DestinationTypes.register("acme/crm", label: "Acme CRM", deliverer: Acme::Crm) do |d|
  #     d.field :list, :string, required: true
  #     d.secret :api_key
  #   end
  module DestinationTypes
    # A bare name is a built-in's; a gem's is `owner/name` (the hook refuses
    # a bare one). Lowercase words, as a block type's name.
    NAME_FORMAT = %r{\A([a-z][a-z0-9_]*/)?[a-z][a-z0-9_]*\z}
    SECRET_FORMAT = /\A[a-z][a-z0-9_]*\z/

    # Raised by a deliverer for a failure worth another attempt: the job
    # retries it.
    class Retry < StandardError; end

    # Raised by a deliverer for a failure that is final: `key` says which
    # (a short word the screens put into words), `line` what the other side
    # answered, scrubbed of secrets by the deliverer.
    class Failed < StandardError
      attr_reader :key, :line

      def initialize(key:, line: nil)
        @key = key.to_s
        @line = line
        super(@key)
      end
    end

    # What a registration's block is handed: `field` with the content
    # model's own checks (`ContentModel::Definition#field`), `secret` for a
    # credential. A setting is one value for the destination, never a
    # translated one, and never a group.
    class Builder
      attr_reader :secrets

      def initialize(name)
        @name = name
        @definition = ContentModel::Definition.new(name)
        @secrets = []
      end

      def field(name, type, **options)
        raise ArgumentError, "#{@name}: a destination's setting is one value, not translated" if options[:translated]
        raise ArgumentError, "#{@name}: a destination's setting is one value, not a #{type}" if ContentModel::Definition::GROUP_TYPES.include?(type)

        @definition.field(name, type, **options)
      end

      def secret(name)
        name = name.to_s
        raise ArgumentError, "#{@name}: a secret is named in lowercase words, not #{name.inspect}" unless name.match?(SECRET_FORMAT)
        raise ArgumentError, "#{@name}: the secret #{name.inspect} is declared twice" if @secrets.include?(name)

        @secrets << name
      end

      def fields
        names = @definition.fields.map(&:name)
        clash = names & @secrets
        raise ArgumentError, "#{@name}: #{clash.join(", ")} is a setting and a secret; a secret is stored apart" if clash.any?

        @definition.fields
      end
    end

    class << self
      def register(name, label:, deliverer:, &definition)
        name = name.to_s
        raise ArgumentError, "#{name.inspect} isn't a destination name (expected mail or owner/name)" unless name.match?(NAME_FORMAT)
        raise ArgumentError, "the destination #{name.inspect} is already registered" if types.key?(name)
        raise ArgumentError, "#{name}: label is the builder's word for the destination, a String" unless label.is_a?(String) && label.present?
        raise ArgumentError, "#{name}: the deliverer answers deliver(delivery, final_attempt:)" unless deliverer.respond_to?(:deliver)

        builder = Builder.new(name)
        definition&.call(builder)
        types[name] = DestinationType.new(name: name, label: label, fields: builder.fields.freeze, secrets: builder.secrets.freeze, deliverer: deliverer)
      end

      def find(name) = types[name.to_s]

      def fetch(name)
        find(name) or raise KeyError, "unknown form destination #{name.inspect} (known: #{names.join(", ")})"
      end

      def names = types.keys

      def all = types.values

      def reset! = types.clear

      # Mail, the one built-in (forms spec, "Destinations"): the form's
      # recipients, one address per line or comma-separated
      # (`Forms::Destinations::Mail`).
      def register_built_ins
        register("mail", label: "Mail", deliverer: Destinations::Mail) do |d|
          d.field :recipients, :text, required: true
        end
      end

      private

      def types = (@types ||= {})
    end
  end
end
