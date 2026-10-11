module Editing
  # The right a person lacks to change a page or a post, by the rule the save
  # services apply: it IS `ContentBlocks::OwnerPermissions` (`edit`, and
  # `publish` too once the record is published, because autosave writes the
  # live record), asked through `AccessControl.allowed?`, so the two cannot
  # drift. A reservation is claimed, released and taken over exactly where a
  # save would be allowed.
  module Rights
    class Check
      include ContentBlocks::OwnerPermissions

      def initialize(actor, record)
        @actor = actor
        @record = record
      end

      def missing = owner_refusal(@record) { |key| AccessControl.allowed?(@actor, key, @record) }
    end

    def self.missing(actor, record) = Check.new(actor, record).missing
  end
end
