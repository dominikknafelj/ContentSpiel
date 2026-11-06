module Admin
  # One toast appended to the layout's `#toasts` region
  # (`Admin::Ui::ToastRegionComponent`) from a Turbo Stream answer, for a
  # response that has no redirect and so no flash to carry the message.
  # `action` is `{ label:, url:, method: }` and `id` the optional DOM id, both
  # as for `Admin::Ui::ToastComponent`. `builder` is the answer's stream
  # builder (a controller's `turbo_stream`, a responder's context's).
  module ToastStream
    def self.for(builder, message, kind: :success, action: nil, id: nil)
      builder.append("toasts", Admin::Ui::ToastComponent.new(message: message, kind: kind, action: action, id: id))
    end
  end
end
