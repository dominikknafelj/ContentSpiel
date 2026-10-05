module Admin
  # One `Setup::SystemCheck::Result` as a row, for CS Studio's System status
  # page and the setup wizard's system-check step (handoff §10 item 14: the
  # wizard "shares rows with System status"): a status chip -- a dot and the
  # word, so the state is never colour alone -- then the check's name, its
  # message and, when the result has one, the console command in a code box
  # with a Copy button.
  #
  # `copyable:` is off in the setup wizard. The wizard loads the `application`
  # entry point only, and `admin--clipboard` is an admin controller, so a Copy
  # button there would be dead; the command is still shown, in a box a visitor
  # can select, and the browser's own copy does the rest.
  #
  # The command is rendered as text (ERB-escaped) and copied from the
  # `text` value; it is a static string (`Setup::SystemCheck::
  # MAIL_FALLBACK_COMMAND`), never built from anything of the viewer's.
  class SystemCheckRowComponent < AdminComponent
    def initialize(result:, copyable: true)
      @result = result
      @copyable = copyable
    end

    private

    attr_reader :result

    def copyable? = @copyable && result.command.present?

    def status_word = result.ok? ? "OK" : "Warning"

    # The border is the second cue beside the dot and the word (handoff: a
    # Warning chip has a warn dot *and* a warn border).
    def chip_class
      border = result.ok? ? "border-line-strong" : "border-warn"
      "inline-flex items-center gap-1.5 rounded-cs border #{border} px-2 py-0.5 font-cs-mono text-label uppercase tracking-mono text-ink"
    end

    def dot_class = result.ok? ? "bg-ok" : "bg-warn"
  end
end
