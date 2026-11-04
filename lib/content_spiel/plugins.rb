# The one registration hook for code outside the CMS (block types spec,
# decision 11): an engine calls
#
#   ContentSpiel::Plugins.block_types do |types|
#     types.register "gallery/album" do |t| … end
#   end
#
# from an `initializer` of its own (Rails' convention). The hook KEEPS the
# block, for the life of the process, and config/initializers/types.rb calls
# every kept block after the built-ins on every `to_prepare`, so a reload
# registers the outside types again against freshly loaded classes, as it
# does the built-ins. An engine's own `to_prepare` would not do: it runs
# before the application's, whose first line is `reset!`.
#
# Required from config/application.rb BEFORE `Bundler.require`, so a gem may
# name the hook whenever its own files are loaded; therefore plain Ruby,
# naming no application constant when it loads, and not reloaded (the kept
# blocks outlive every reload). A name `Admin::ContentSpiel` would shadow
# this module (test/lib/admin_namespace_shadow_test.rb).
module ContentSpiel
  module Plugins
    Hook = Data.define(:block, :location)

    # What a hook's block is handed: `register` with the registry's own
    # signature, refusing a bare name (the built-ins'), a second owner in
    # one call, and an owner another hook has registered under in this
    # replay (`owners`: owner => the place of the hook that took it), since
    # an owner's prefix is what keeps two gems' tokens apart.
    #
    # `kind` says what is being registered, for the message ("a block type
    # from outside"), and `build` how one is made of a name and what the hook
    # gave: a block type's definition block, a form field type's attributes.
    class Registrar
      def initialize(registry, location, owners = {}, kind: "block type", build: nil)
        @kind = kind
        @build = build || ->(name, arguments, definition) { registry.register(name, &definition) }
        @registry = registry
        @location = location
        @owners = owners
        @owner = nil
      end

      def register(name, *arguments, **keywords, &definition)
        name = name.to_s
        owner, rest = name.split("/", 2)
        raise ArgumentError, "#{name.inspect}: a #{@kind} from outside is named owner/name (gallery/album); a bare name is a built-in's" if rest.nil?

        @owner ||= owner
        raise ArgumentError, "#{name.inspect}: one call of the hook registers the types of one owner, and #{@owner.inspect} came first" unless owner == @owner

        taken = @owners[owner]
        if taken && taken != @location
          raise ArgumentError, "#{name.inspect}: the owner #{owner.inspect} is another hook's, called at #{taken}; one owner is one gem's"
        end
        @owners[owner] = @location

        @build.call(name, keywords, definition)
      end
    end

    # The words a hook's error is given (`register_block_types`), which the
    # theme's refusal on a reload looks for (`Theme.not_registered`).
    REPLAYED = "ContentSpiel::Plugins.block_types, called at".freeze

    # One hook list per registry: a hook is replayed into its own registry
    # only, in the order it was called.
    @hooks = { block_types: [], form_field_types: [] }

    class << self
      def block_types(&block)
        raise ArgumentError, "ContentSpiel::Plugins.block_types takes a block" unless block

        keep(:block_types, block, caller_locations(1, 1).first)
      end

      # The same for the form field types (forms plan, Task 1):
      #
      #   ContentSpiel::Plugins.form_field_types do |types|
      #     types.register "acme/rating", value_type: :integer, label: "Rating", options: [],
      #       max_length: nil, summary: false, input: Acme::RatingComponent, display: ->(value, field, locale:) { value.to_s }
      #   end
      #
      # The owner rules are the block types'; the arguments are
      # `Forms::FieldType`'s members.
      def form_field_types(&block)
        raise ArgumentError, "ContentSpiel::Plugins.form_field_types takes a block" unless block

        keep(:form_field_types, block, caller_locations(1, 1).first)
      end

      # Every kept block, in the order the hooks were called (the Gemfile's
      # order), each with a registrar of its own. Whatever a block raises is
      # raised again, as the same class, with the place of the hook's call in
      # the message, so a site's log names the gem that stopped the boot.
      def register_block_types(registry)
        replay(:block_types, REPLAYED) { |location, owners| Registrar.new(registry, location, owners) }
      end

      # Every kept form field type hook, replayed the same way into
      # `Forms::FieldTypes` (the registry takes a built `Forms::FieldType`).
      def register_form_field_types(registry)
        replay(:form_field_types, "ContentSpiel::Plugins.form_field_types, called at") do |location, owners|
          Registrar.new(registry, location, owners, kind: "form field type",
            build: ->(name, attributes, _definition) { registry.register(Forms::FieldType.new(name: name, **attributes)) })
        end
      end

      # Tests only: a hook a test kept is taken out again.
      def remove(hook) = @hooks.each_value { |hooks| hooks.delete(hook) }

      private

      def keep(list, block, place)
        Hook.new(block: block, location: "#{place.path}:#{place.lineno}").tap { |hook| @hooks[list] << hook }
      end

      def replay(list, words)
        owners = {}
        @hooks[list].each do |hook|
          hook.block.call(yield(hook.location, owners))
        rescue StandardError => error
          raise error.exception("#{error.message} (#{words} #{hook.location})")
        end
      end
    end
  end
end
