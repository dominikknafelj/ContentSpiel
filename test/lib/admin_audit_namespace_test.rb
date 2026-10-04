require "test_helper"

# The `Admin::Media` trap (`test/lib/admin_media_namespace_test.rb`), for the
# audit log: an `Admin::Audit` module -- the obvious name for the audit
# screens' components, which live under `Admin::AuditScreen` instead -- would
# shadow the top-level `Audit` module (`app/models/audit.rb`,
# `Audit::Event`/`Snapshot`/`Sentence`/`Filter`) for every bare `Audit::`
# reference lexically nested under `module Admin` (the audit controller, the
# dashboard and trash components all have one).
module Admin
  module AuditNamespaceProbe
    def self.resolve_sentence
      Audit::Sentence
    end
  end
end

class AdminAuditNamespaceTest < ActiveSupport::TestCase
  setup { Rails.application.eager_load! }

  test "nothing defines Admin::Audit" do
    assert_not Admin.const_defined?(:Audit, false),
      "Admin::Audit exists, which would shadow the top-level Audit module for every bare Audit:: " \
        "reference lexically nested under module Admin -- see Admin::AuditScreen's own comment"
  end

  test "a bare Audit:: reference lexically nested under Admin still resolves to the top-level model" do
    assert_equal Audit::Sentence, Admin::AuditNamespaceProbe.resolve_sentence
  end
end
