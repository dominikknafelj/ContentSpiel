module Admin
  # The flash for a CS Studio screen: the `role="status"` notice and
  # `role="alert"` alert paragraphs every index view used to repeat by hand,
  # plus an optional one-click follow-up (trash spec §7 -- "Moved “About” to
  # the trash" with an Undo, Task 10). The action is a `button_to`, never a
  # link: every follow-up it exists for is a write (a restore is a POST),
  # and a GET link would be one prefetch or crawler away from performing it.
  #
  # `action` is `{ label:, url:, method: :post }` -- `method` other than
  # `:post` goes through Rails' `_method` override the way `button_to`
  # always does. Messages are plain Strings and stay auto-escaped; a flash
  # that needs a link carries it as `action`, never as `html_safe` markup
  # inside the message.
  class FlashComponent < AdminComponent
    def initialize(notice:, alert:, action: nil)
      @notice = notice
      @alert = alert
      @action = action
    end

    def render? = notice.present? || alert.present?

    private

    attr_reader :notice, :alert, :action

    def action_method = action.fetch(:method, :post)
  end
end
