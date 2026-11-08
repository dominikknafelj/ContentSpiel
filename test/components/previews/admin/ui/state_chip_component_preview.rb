module Admin
  module Ui
    # `Admin::Ui::StateChipComponent`: its four tones, each with a word a
    # caller passes; `ok` with a detail after the chip.
    class StateChipComponentPreview < ViewComponent::Preview
      def ok = render(Admin::Ui::StateChipComponent.new(tone: :ok, label: "Key saved", detail: "added 2 Oct"))

      def warn = render(Admin::Ui::StateChipComponent.new(tone: :warn, label: "Saved, not tested"))

      def danger = render(Admin::Ui::StateChipComponent.new(tone: :danger, label: "Last send failed"))

      def off = render(Admin::Ui::StateChipComponent.new(tone: :off, label: "Not set up"))
    end
  end
end
