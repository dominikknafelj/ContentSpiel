module Admin
  module Ui
    # `Admin::Ui::NoticeComponent`: its four tones, the compact size, and a
    # long German sentence that wraps inside its container.
    class NoticeComponentPreview < ViewComponent::Preview
      LONG = "Diese Verbindung ist nicht verschlüsselt. Passwörter und Sitzungen können unterwegs mitgelesen werden. " \
             "Tragen Sie für PUBLIC_HOST eine https-Adresse ein und laden Sie die Seite dann neu, bevor Sie sich mit Ihrem Zugang wieder hier anmelden.".freeze

      def warn = render(Admin::Ui::NoticeComponent.new(tone: :warn).with_content("Only the owner can delete the owner's account."))

      def ok = render(Admin::Ui::NoticeComponent.new(tone: :ok).with_content("Password changed."))

      def danger = render(Admin::Ui::NoticeComponent.new(tone: :danger).with_content("This reset link has expired. Ask for a new one."))

      def neutral = render(Admin::Ui::NoticeComponent.new(tone: :neutral).with_content("Built-in groups can be changed but not deleted."))

      def compact = render(Admin::Ui::NoticeComponent.new(tone: :warn, size: :compact).with_content("That email and password don't match."))

      def long = render(Admin::Ui::NoticeComponent.new(tone: :warn).with_content(LONG))
    end
  end
end
