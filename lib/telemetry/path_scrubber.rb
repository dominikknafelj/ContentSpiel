module Telemetry
  # Takes a password-reset token out of a request's address, and the query
  # string off it (`scrub_attribute` says why), before a span that holds the
  # address leaves the process.
  #
  # The token was a segment of two routes, `GET <admin>/password/:token/edit`
  # and `PATCH <admin>/password/:token`, and the Rack instrumentation writes
  # the path of every request into its span (`url.path`, and `http.target`
  # with the older attribute names). Whoever reads the spans, in a terminal
  # or in a tracing backend, could reset that person's password for as long
  # as the token was good. The reset link has since moved the token out of
  # the path; this stays for the old link, which still answers (with a
  # redirect), and for whatever a client goes on sending to the old address.
  #
  # The rule is wider than the two routes, because a path is recorded before
  # the router has said whether it is one of ours: the segment that follows
  # `<admin>/password/` is filtered wherever something follows it, and where
  # it is the last one unless it is `new` or `edit`, the two addresses of
  # that shape that carry no token. So a link a mail program has spoilt
  # (a bracket taken into it, a slash doubled) is filtered too, and a path
  # that is filtered without need costs a reader nothing.
  module PathScrubber
    FILTERED = "[FILTERED]".freeze

    # Under `<admin>/password/`, as a last segment: the request form and the
    # reset form. Neither is a token.
    NOT_A_TOKEN = %w[new edit].freeze

    # The attributes that hold a request's address or a part of it, in the
    # stable HTTP conventions (`url.*`) and in the older ones (`http.*`):
    # the path alone, the query alone, and the three that may hold both.
    PATH = "url.path".freeze
    QUERY = "url.query".freeze
    ADDRESSES = %w[http.target url.full http.url].freeze
    ATTRIBUTES = [ PATH, QUERY, *ADDRESSES ].freeze

    # What may follow a segment that is the last one: slashes, then the end
    # or a query or a fragment.
    LAST_SEGMENT = %r{\A/*(?:[?#]|\z)}
    private_constant :LAST_SEGMENT

    # `admin_path` is read when a path is scrubbed, not when this file is
    # loaded: `ContentSpiel::ADMIN_PATH` is defined by an initializer
    # (`config/initializers/admin_path.rb`) and this file is loaded before
    # any of them.
    def self.scrub(path, admin_path: ContentSpiel::ADMIN_PATH)
      return path unless path.is_a?(String)

      match = pattern(admin_path).match(path)
      return path unless match
      return path if NOT_A_TOKEN.include?(match[:segment]) && match[:rest].match?(LAST_SEGMENT)

      "#{match[:lead]}#{FILTERED}#{match[:rest]}"
    end

    # One attribute of a span as it may leave the process. Two rules:
    #
    # The path is scrubbed as above, wherever it stands.
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
      when PATH then scrub(value)
      when QUERY then value.empty? ? value : FILTERED
      when *ADDRESSES then scrub(without_query(value))
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

    # A path, or a whole address (`url.full`), whose first two segments are
    # the admin path and `password`. The router squeezes doubled slashes
    # before it matches, so `//cs-studio//password//<token>` reaches the
    # same action and is matched here as well; it compares the two words
    # exactly, so neither another case nor a percent-escape of one is.
    def self.pattern(admin_path)
      (@patterns ||= {})[admin_path] ||=
        %r{\A(?<lead>(?:(?i:[a-z][a-z0-9+.\-]*)://[^/?#]*)?/+#{Regexp.escape(admin_path)}/+password/+)(?<segment>[^/?#]+)(?<rest>.*)\z}m
    end
    private_class_method :pattern

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
