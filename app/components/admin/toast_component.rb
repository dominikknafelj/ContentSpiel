module Admin
  # One toast (handoff §10): a transient message at the foot of the screen
  # that replaced the inline `Admin::FlashComponent` paragraphs. `kind` picks
  # the live-region role and how long it stays:
  #
  #   success  role=status  4 s
  #   undo     role=status  8 s  (a trash move, with its Undo `action`)
  #   warning  role=alert   until dismissed
  #   error    role=alert   until dismissed
  #
  # A failure never auto-hides: it is the one thing the editor must not miss
  # because they looked away for five seconds. The clock itself is
  # `admin--toast` (it pauses on hover and focus, so an Undo can't vanish
  # under the pointer).
  #
  # `action` is `{ label:, url:, method: :post }` -- a `button_to`, never a
  # link, because every follow-up it exists for is a write (a restore is a
  # POST) and a GET link would be one prefetch away from performing it. Keys
  # may be strings: `flash[:undo]` comes back from the session JSON-encoded.
  # The message is a plain String and stays auto-escaped; a toast that needs
  # a link carries it as `action`, never as `html_safe` markup in the message.
  class ToastComponent < AdminComponent
    KINDS = %i[success undo warning error].freeze
    TIMEOUTS = { success: 4000, undo: 8000, warning: 0, error: 0 }.freeze

    def initialize(message:, kind: :success, action: nil)
      raise ArgumentError, "unknown toast kind #{kind.inspect}" unless KINDS.include?(kind.to_sym)

      @message = message
      @kind = kind.to_sym
      @action = action&.to_h&.with_indifferent_access
    end

    def render? = message.present?

    private

    attr_reader :message, :kind, :action

    def role = %i[warning error].include?(kind) ? "alert" : "status"

    def timeout = TIMEOUTS.fetch(kind)

    def action_method = action.fetch(:method, :post)
  end
end
