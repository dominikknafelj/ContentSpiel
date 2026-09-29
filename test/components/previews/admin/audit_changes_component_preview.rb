module Admin
  # `Admin::AuditChangesComponent` (design spec §5, Task 9): the old/new
  # table an audit event's show page renders `field_changes` through.
  class AuditChangesComponentPreview < ViewComponent::Preview
    # Plain and translated columns: a two-element `[old, new]` array per
    # field, exactly `Audit::Snapshot.field_changes_for`'s own shape.
    def scalar_changes
      render Admin::AuditChangesComponent.new(field_changes: {
        "en title" => [ "Draft", "Published" ],
        "published_at" => [ nil, "2026-09-28T10:00:00Z" ],
        "tag_names" => [ [], [ "ruby" ] ]
      })
    end

    # A rich-text body's own shape -- rendered as "Changed", never the raw
    # digests (`Audit::Snapshot.field_changes_for`'s own comment).
    def body_changed
      render Admin::AuditChangesComponent.new(field_changes: {
        "en body" => { "digest_before" => "3a7c…", "digest_after" => "91fe…" }
      })
    end

    # Task 9 controller ruling: a stored value that looks like markup
    # renders as plain text, never `html_safe`.
    def html_in_a_value_is_escaped
      render Admin::AuditChangesComponent.new(field_changes: {
        "en title" => [ "<script>alert(1)</script>", "Safe title" ]
      })
    end

    def no_changes
      render Admin::AuditChangesComponent.new(field_changes: {})
    end
  end
end
