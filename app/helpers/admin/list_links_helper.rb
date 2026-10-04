module Admin
  # The query params a list's own links (pager, "Load older") carry along.
  # Never `request.query_parameters` wholesale: handed to a route helper, a
  # key like `script_name`, `host`, `anchor`, `only_path` or `format` is read
  # as a URL *option*, not a query param (`?script_name=//evil.example` makes
  # a protocol-relative link). Each list names the filter keys it really has;
  # only those, and only plain string values, survive, plus the editing
  # `locale`.
  module ListLinksHelper
    def list_params(*keys)
      allowed = keys.map(&:to_s) | %w[locale]
      request.query_parameters.slice(*allowed).select { |_, value| value.is_a?(String) }
    end
  end
end
