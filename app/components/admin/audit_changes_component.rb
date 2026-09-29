module Admin
  # The old/new changes table on an audit event's page (design spec §5
  # "Audit log module": "the event page shows the changes table (old/new;
  # bodies as 'changed')"). `field_changes` is `Audit::Event#field_changes`
  # (access-control design spec §4.1): `{field => [old, new]}` for a plain
  # or translated column, `{field => {"digest_before"=>, "digest_after"=>}}`
  # for a rich-text body (`Audit::Snapshot.field_changes_for`'s own
  # comment) -- the latter renders as "Changed" rather than two
  # content-free digests, which would read as if they were the content
  # but aren't.
  #
  # Every value renders through `#display`, and ERB's own `<%= %>`
  # escaping does the rest -- never `html_safe` on a stored value (global
  # constraints; Task 9 controller ruling: a title of literal `<script>`
  # must render as text, not markup) -- so nothing another editor once
  # typed into a field can run as HTML on this page.
  class AuditChangesComponent < AdminComponent
    def initialize(field_changes:)
      @field_changes = field_changes || {}
    end

    attr_reader :field_changes

    def body_change?(value) = value.is_a?(Hash)

    def old_value(value) = value.is_a?(Array) ? value[0] : nil

    def new_value(value) = value.is_a?(Array) ? value[1] : nil

    def display(value)
      case value
      when nil then "—"
      when Array, Hash then value.to_json
      else value.to_s
      end
    end
  end
end
