module Telemetry
  # Takes the query string off a request's address before a span that holds
  # the address leaves the process (`scrub_attribute` says why).
  #
  # The password-reset token is not in any address that reaches the server: it
  # follows the "#" of the mailed link, which a browser never sends, and the
  # page's script sends it in a request body (`password/check`, `password`).
  # A `token` handed in a query string is cut with every other query.
  module PathScrubber
    FILTERED = "[FILTERED]".freeze

    # The attributes that hold a request's address or a part of it, in the
    # stable HTTP conventions (`url.*`) and in the older ones (`http.*`):
    # the path alone, the query alone, and the three that may hold both.
    PATH = "url.path".freeze
    QUERY = "url.query".freeze
    ADDRESSES = %w[http.target url.full http.url].freeze
    ATTRIBUTES = [ PATH, QUERY, *ADDRESSES ].freeze

    # One attribute of a span as it may leave the process.
    #
    # NO QUERY STRING LEAVES IN A SPAN, whatever its parameters are called:
    # `url.query` is replaced whole, and an address is cut at its first "?".
    # The Action Pack instrumentation does put the app's `filter_parameters`
    # over the query, but only once a controller has the request. One that
    # is answered before any controller (a redirect in the routes, a
    # throttle, a refusal in a middleware) keeps the query as it was sent,
    # and with the older attribute names `http.target` is never rewritten
    # at all. A note's quote travels in a query string (`note_quote`), and a
    # note's text reaches no log line, so none of it is kept; `http.route`
    # still says which address was asked for.
    #
    # An attribute that is none of ATTRIBUTES, a value that is no string and
    # a value with nothing to take out are handed back as they are, the very
    # object, which is how a caller sees that nothing changed.
    def self.scrub_attribute(key, value)
      return value unless value.is_a?(String)

      case key
      when QUERY then value.empty? ? value : FILTERED
      when *ADDRESSES then without_query(value)
      else value
      end
    end

    # The attributes with each of ATTRIBUTES scrubbed: the very hash it was
    # given when there is nothing to change, a frozen copy otherwise.
    def self.scrub_attributes(attributes)
      return attributes if attributes.nil?

      changed = nil
      ATTRIBUTES.each do |key|
        value = attributes[key]
        scrubbed = scrub_attribute(key, value)
        (changed ||= {})[key] = scrubbed unless scrubbed.equal?(value)
      end

      changed ? attributes.merge(changed).freeze : attributes
    end

    # Everything from the first "?" goes, a fragment after it included.
    def self.without_query(address)
      at = address.index("?")
      at ? address[0, at] : address
    end
    private_class_method :without_query

    # First in the list of span processors: the address attributes a span is
    # started with (all the Rack instrumentation writes, the path and the
    # query both) are scrubbed before any other processor, or anything that
    # reads the running span, has seen them.
    #
    # It can do nothing for an attribute set later. The SDK freezes a span's
    # attributes before it calls `on_finish`, and its `on_finishing` hook,
    # which runs just before that, is called while the span holds its own
    # mutex, where `set_attribute` (which takes the same mutex) raises. Those
    # are scrubbed by `Exporter` below, on their way out.
    class Processor
      def on_start(span, _parent_context)
        attributes = span.attributes
        return if attributes.nil?

        ATTRIBUTES.each do |key|
          value = attributes[key]
          scrubbed = PathScrubber.scrub_attribute(key, value)
          span.set_attribute(key, scrubbed) unless scrubbed.equal?(value)
        end
      end

      # Nothing to do, and nothing that could be done: see the class comment.
      def on_finish(_span); end

      def force_flush(timeout: nil) = OpenTelemetry::SDK::Trace::Export::SUCCESS
      def shutdown(timeout: nil) = OpenTelemetry::SDK::Trace::Export::SUCCESS
    end

    # Wraps the exporter the spans are sent through, whichever it is: every
    # span's attributes are scrubbed in the copy that is exported (a span's
    # own data is frozen by then), so it does not matter when an attribute
    # was set or by which instrumentation.
    class Exporter
      def initialize(exporter)
        @exporter = exporter
      end

      def export(spans, timeout: nil)
        @exporter.export(Array(spans).map { |span| scrubbed(span) }, timeout: timeout)
      end

      def force_flush(timeout: nil) = @exporter.force_flush(timeout: timeout)
      def shutdown(timeout: nil) = @exporter.shutdown(timeout: timeout)

      private
        def scrubbed(span)
          attributes = PathScrubber.scrub_attributes(span.attributes)
          return span if attributes.equal?(span.attributes)

          span.dup.tap { |copy| copy.attributes = attributes }
        end
    end
  end
end
