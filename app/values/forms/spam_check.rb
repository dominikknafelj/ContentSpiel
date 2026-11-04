module Forms
  # A form's own spam measures (forms spec, "Sending"; no third-party
  # captcha), asked of a visitor's send before anything is cleaned or
  # written:
  #
  #   Forms::SpamCheck.call(params, form: form, now: Time.current)
  #   # => nil (no trip) | :honeypot | :too_soon | :invalid_token
  #
  # - `:honeypot`: the field `website` holds anything. The Form block draws
  #   it hidden from people and screen readers (`hidden` wrapper,
  #   `aria-hidden`, `tabindex="-1"`, `autocomplete="off"`), so only a
  #   script that fills every field fills it.
  # - `:too_soon`: the signed draw time (`Forms::Drawn`) is under
  #   `Forms::Drawn::MIN_SECONDS`: nobody reads and fills a form that fast.
  # - `:invalid_token`: no draw time, one of another form, or one that was
  #   changed (`Forms::Drawn.check` answers `:invalid`; named for the
  #   measure here, since a log line says which measure tripped).
  #
  # A TRIP IS ANSWERED EXACTLY AS A SUCCESS (`FormSendsController`): the
  # form's thank-you, stored nowhere, no event, one log line naming the form
  # and the measure, so a bot learns nothing from the answer. The rate limit
  # is the controller's (`Forms::SendLimit`) and is said to the visitor
  # (owner's ruling 1).
  module SpamCheck
    HONEYPOT = "website".freeze

    module_function

    def call(params, form:, now: Time.current)
      return :honeypot if params[HONEYPOT].present?

      case Drawn.check(params["drawn"], form: form, now: now)
      when :ok then nil
      when :too_soon then :too_soon
      else :invalid_token
      end
    end
  end
end
