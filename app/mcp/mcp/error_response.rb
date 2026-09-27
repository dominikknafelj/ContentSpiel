# Shared by every Post MCP tool (list/get/create/update): one place to turn
# a user-facing failure -- a missing id, an unsupported locale, a failed
# `Posts::Save` -- into the MCP error-response shape, rather than each tool
# repeating the `MCP::Tool::Response.new([...], error: true)` literal.
# `extend`ed (not `include`d) because every tool's `.call` is itself a class
# method.
#
# Lives at app/mcp/mcp/error_response.rb, not app/mcp/error_response.rb:
# Rails autoloads every app/* subdirectory as its own Zeitwerk root, so
# app/mcp itself would map to the top-level namespace, not `Mcp` --
# app/mcp/error_response.rb would resolve to ::ErrorResponse, not
# Mcp::ErrorResponse. Nesting a `mcp/` directory one level inside that root
# is what gives every file below it the `Mcp::` prefix (`bin/rails
# zeitwerk:check` verifies this), with no `app/mcp` namespace configuration
# needed.
module Mcp
  module ErrorResponse
    def error_response(message)
      MCP::Tool::Response.new([ { type: "text", text: message } ], error: true)
    end

    # `Locales::SUPPORTED` (all ~40 codes ContentSpiel can ever serve) is what
    # every tool's `locale` schema enum has to list, because `input_schema` is
    # built once at class load and can't read a per-site runtime setting --
    # but a given site only actually serves `Locales.enabled`, so a schema-
    # valid locale can still be one this site hasn't turned on. This is the
    # call-time check that catches that gap, in place of the
    # `Mobility.available_locales` guard the schema itself used to provide for
    # free before it was widened (spec §7.3).
    def reject_unless_enabled(locale)
      return nil if Locales.enabled?(locale)

      error_response("#{locale.inspect} is not an enabled language")
    end
  end
end
