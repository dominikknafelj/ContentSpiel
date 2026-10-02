module AI
  module Providers
    # The built-in provider (translation helpers spec §6.1): Anthropic's
    # Messages API through the official `anthropic` gem, one request per
    # `#translate` call however many texts it carries.
    #
    # `client:` is injectable so tests hand in a fake and never reach the
    # network; left out, it's a real `::Anthropic::Client` (`::` throughout
    # -- inside this class, a bare `Anthropic` is this class itself).
    class Anthropic
      # Every text goes out after a marker line of its own, `<<<1>>>`,
      # `<<<2>>>`, ..., and the answer is expected in the same shape -- so
      # the reply splits back into exactly one translation per text, in
      # order, or the call fails. Matched only as a whole line: angle
      # brackets tripled around a number never occur on a line of their own
      # in prose or Markdown (a text that does contain one is refused before
      # anything is sent, `#check_texts!`).
      MARKER = /^<<<(\d+)>>>[ \t]*\r?\n?/

      # The fixed instructions (spec §6.1). `%{from}`/`%{to}` are English
      # language names (`Locales.name`), never codes: a model translates
      # "into German" more reliably than "into de". The reply-format
      # paragraph is what `#parse` relies on; changing one means changing
      # the other.
      SYSTEM_PROMPT = <<~PROMPT.freeze
        You translate website content from %{from} to %{to}.

        Translate faithfully: keep the meaning, tone and level of formality, and keep proper names (people, places, products, brands) as they are. Don't add, drop or explain anything.

        The user message holds one or more texts. Each starts with a marker line such as <<<1>>>, <<<2>>> and so on. Reply with the same marker lines, in the same order, each followed by the translation of that text and nothing else. Return only the translations: no introduction, notes or comments.
        %{format_rules}
      PROMPT

      # Only for `format: :markdown` (rich-text bodies sent as `RichText::
      # Document#to_markdown`, spec §6.3): what must survive the round trip
      # back through `RichText::Document.from_markdown` unchanged -- the
      # structure, the `::youtube{…}`/`::image{…}` directive lines and the
      # `cs:page/42`/`cs:post/7` internal link targets (see "Rich text" in
      # CLAUDE.md).
      MARKDOWN_RULES = <<~RULES.freeze

        The texts are Markdown. Keep the Markdown structure exactly: headings, lists, quotes, emphasis, code and line breaks. Never translate code. Keep every line that starts with :: (a directive such as ::youtube{id="…"} or ::image{asset="42" alt="…"}) exactly as it is. Keep every link target unchanged, including internal targets such as cs:page/42 and cs:post/7; translate only the link text.
      RULES

      FORMATS = %i[plain markdown].freeze

      # Translation helpers global constraints: 60 s. Retries are off: this
      # runs inside an editor's web request, and the SDK's default retries
      # would let one click hang for several timeouts in a row -- a clear
      # "try again" message straight away is the better answer.
      TIMEOUT = 60
      MAX_RETRIES = 0

      # Enough for the largest request `AI::Translate` sends (30,000
      # characters, spec §6.3) in a language that runs longer than the
      # original. An answer that still hits it is reported as such
      # (`#check_complete!`) rather than as a count mismatch.
      MAX_TOKENS = 16_000

      # The SDK otherwise reads `ANTHROPIC_BASE_URL` from the server's
      # environment; the site's own key only ever goes to Anthropic.
      BASE_URL = "https://api.anthropic.com".freeze

      def initialize(api_key:, model:, client: nil)
        # A blank key would make the SDK fall back to the server's own
        # `ANTHROPIC_API_KEY` -- never what a site's settings meant.
        raise AI::Error, AI::NOT_CONFIGURED if api_key.blank? && client.nil?

        @model = model.presence || AI::DEFAULT_MODEL
        @client = client || ::Anthropic::Client.new(api_key: api_key, base_url: BASE_URL, timeout: TIMEOUT, max_retries: MAX_RETRIES)
      end

      def translate(texts:, from:, to:, format:)
        format = format.to_sym
        raise ArgumentError, "format must be one of #{FORMATS.join(", ")}" unless FORMATS.include?(format)
        return [] if texts.empty?

        check_texts!(texts)
        response = request do
          @client.messages.create(
            model: @model,
            max_tokens: MAX_TOKENS,
            system: system_prompt(from, to, format),
            messages: [ { role: "user", content: numbered(texts) } ]
          )
        end
        check_complete!(response)

        parse(response_text(response), texts: texts)
      end

      # The smallest real request there is: proves the key, the model name
      # and the network path in one go (an unknown model is a 404, which
      # `#request` reports as such).
      def test_connection
        request { @client.messages.create(model: @model, max_tokens: 1, messages: [ { role: "user", content: "Hi" } ]) }
        true
      end

      private

      def system_prompt(from, to, text_format)
        SYSTEM_PROMPT % {
          from: ::Locales.name(from), to: ::Locales.name(to),
          format_rules: text_format == :markdown ? MARKDOWN_RULES : ""
        }
      end

      def numbered(texts)
        texts.each_with_index.map { |text, index| "<<<#{index + 1}>>>\n#{text}" }.join("\n")
      end

      def check_texts!(texts)
        return unless texts.any? { |text| text.to_s.match?(MARKER) }

        raise AI::Error, "This text contains a line the translator uses internally (<<<1>>>) and can't be sent."
      end

      def response_text(response)
        Array(response.content).select { |block| block.type.to_s == "text" }.map(&:text).join
      end

      def check_complete!(response)
        return unless response.stop_reason.to_s == "max_tokens"

        raise AI::Error, "The translation was too long to finish — translate in parts."
      end

      # Everything before the first marker is ignored (a model that says
      # "Here you go:" anyway); each marker must be the next number in
      # sequence, and there must be exactly one per text.
      #
      # Only the newlines around each translation are trimmed, never spaces:
      # a Markdown body may start with an indented code block or end inside
      # a nested list item, and stripping that indentation changes what it
      # parses as. An empty translation of a non-empty text is a failed
      # answer, not a suggestion to blank the field.
      def parse(text, texts:)
        count = texts.size
        parts = text.split(MARKER)
        parts.shift # whatever came before the first marker
        pairs = parts.each_slice(2).to_a

        numbers = pairs.map { |number, _| number.to_i }
        unless numbers == (1..count).to_a
          raise AI::Error, "The AI provider's answer didn't match the request (expected #{count} #{"translation".pluralize(count)}, got #{numbers.size}). Try again."
        end

        translations = pairs.map { |_, translation| translation.to_s.gsub(/\A(?:\r?\n)+|(?:\r?\n)+\z/, "") }
        if translations.zip(texts).any? { |translation, source| translation.blank? && source.present? }
          raise AI::Error, "The provider returned an empty translation. Try again."
        end

        translations
      end

      # Maps the SDK's errors (anthropic gem, `Anthropic::Errors`) to the
      # messages an editor sees. Never `error.message`: for a status error
      # the SDK builds it from the URL and the response body.
      # `APITimeoutError` is a subclass of `APIConnectionError`, and every
      # status error a subclass of `APIStatusError`, so order matters.
      def request
        yield
      rescue ::Anthropic::Errors::AuthenticationError, ::Anthropic::Errors::PermissionDeniedError
        raise AI::Error, "The AI provider refused the API key — check it in Settings."
      rescue ::Anthropic::Errors::RateLimitError
        raise AI::Error, "The AI provider's rate limit was reached — wait a minute and try again."
      rescue ::Anthropic::Errors::NotFoundError
        raise AI::Error, "The AI provider doesn't know the model “#{@model}” — check the model name in Settings."
      rescue ::Anthropic::Errors::InternalServerError
        raise AI::Error, "The AI provider is busy or having trouble right now — try again in a little while."
      rescue ::Anthropic::Errors::APIStatusError => error
        raise AI::Error, "The AI provider refused the request (status #{error.status})."
      rescue ::Anthropic::Errors::APITimeoutError
        raise AI::Error, "The AI provider didn't answer in time — try again, or translate less at once."
      rescue ::Anthropic::Errors::APIConnectionError
        raise AI::Error, "Couldn't reach the AI provider — check the server's internet connection."
      rescue ::Anthropic::Errors::Error
        raise AI::Error, "The AI provider request failed — try again."
      end
    end
  end
end
