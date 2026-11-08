module Admin
  module SettingsScreen
    # `Admin::SettingsScreen::CardComponent`, the frame of every Settings
    # card: the head alone, with an intro, and with both head slots filled.
    class CardComponentPreview < ViewComponent::Preview
      def heading_only
        render(Admin::SettingsScreen::CardComponent.new(section: SettingsSections.find("publishing"))) { body }
      end

      def with_intro
        render(Admin::SettingsScreen::CardComponent.new(section: SettingsSections.find("images"), intro: "How the images of the library are made for the public site.")) { body }
      end

      def with_head_slots
        render(Admin::SettingsScreen::CardComponent.new(section: SettingsSections.find("mail"), intro: "Password reset links and invites.")) do |card|
          card.with_head_end { "<span class=\"text-sm text-meta\">End</span>".html_safe }
          card.with_head_note { "<p class=\"mt-2 text-sm text-dim\">A note under the intro.</p>".html_safe }
          body
        end
      end

      private

      def body = "<div class=\"p-4 text-sm text-ink\">The card's fields.</div>".html_safe
    end
  end
end
