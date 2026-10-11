module Editing
  # The right a person lacks to change a page or a post, by the rule the save
  # services apply: `AccessControl::OwnerRule` (`edit`, and `publish` too once
  # the record is published, because autosave writes the live record), the
  # very rule `ContentBlocks::OwnerPermissions` delegates to, asked through
  # `AccessControl.allowed?`, so the two cannot drift. A reservation is
  # claimed, released and taken over exactly where a save would be allowed.
  module Rights
    def self.missing(actor, record)
      AccessControl::OwnerRule.refusal(record) { |key| AccessControl.allowed?(actor, key, record) }
    end
  end
end
