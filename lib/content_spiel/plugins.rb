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
    # signature, refusing a bare name (the built-ins') and a second owner in
    # one call.
    class Registrar
      def initialize(registry, location)
        @registry = registry
        @location = location
        @owner = nil
      end

      def register(name, &definition)
        name = name.to_s
        owner, rest = name.split("/", 2)
        raise ArgumentError, "#{name.inspect}: a block type from outside is named owner/name (gallery/album); a bare name is a built-in's" if rest.nil?

        @owner ||= owner
        raise ArgumentError, "#{name.inspect}: one call of the hook registers the types of one owner, and #{@owner.inspect} came first" unless owner == @owner

        @registry.register(name, &definition)
      end
    end

    # The words a hook's error is given (`register_block_types`), which the
    # theme's refusal on a reload looks for (`Theme.not_registered`).
    REPLAYED = "ContentSpiel::Plugins.block_types, called at".freeze

    @hooks = []

    class << self
      def block_types(&block)
        raise ArgumentError, "ContentSpiel::Plugins.block_types takes a block" unless block

        Hook.new(block: block, location: caller_locations(1, 1).first.then { |place| "#{place.path}:#{place.lineno}" }).tap { |hook| @hooks << hook }
      end

      # Every kept block, in the order the hooks were called (the Gemfile's
      # order), each with a registrar of its own. Whatever a block raises is
      # raised again, as the same class, with the place of the hook's call in
      # the message, so a site's log names the gem that stopped the boot.
      def register_block_types(registry)
        @hooks.each do |hook|
          hook.block.call(Registrar.new(registry, hook.location))
        rescue StandardError => error
          raise error.exception("#{error.message} (#{REPLAYED} #{hook.location})")
        end
      end

      # Tests only: a hook a test kept is taken out again.
      def remove(hook) = @hooks.delete(hook)
    end
  end
end
