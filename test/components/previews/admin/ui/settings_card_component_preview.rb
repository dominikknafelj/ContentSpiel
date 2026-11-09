module Admin
  module Ui
    # `Admin::Ui::SettingsCardComponent`, the frame of a settings-style card:
    # one example for each state it declares.
    class SettingsCardComponentPreview < ViewComponent::Preview
      def rest
        render(Admin::Ui::SettingsCardComponent.new(heading_id: "preview-publishing", heading: "Publishing", icon: :file_text, family: :lists)) { body }
      end

      def intro
        render(Admin::Ui::SettingsCardComponent.new(heading_id: "preview-images", heading: "Images", icon: :image, family: :media, intro: "How the images of the library are made for the public site.")) { body }
      end

      def head_end
        render(Admin::Ui::SettingsCardComponent.new(heading_id: "preview-mail", heading: "Mail", icon: :at_sign, family: :media, intro: "Password reset links and invites.")) do |card|
          card.with_head_end { "<span class=\"text-sm text-meta\">End</span>".html_safe }
          body
        end
      end

      def head_note
        render(Admin::Ui::SettingsCardComponent.new(heading_id: "preview-languages", heading: "Languages", icon: :translations, family: :text, intro: "Which languages the site speaks.")) do |card|
          card.with_head_note { "<p class=\"mt-2 text-sm text-dim\">A note under the intro.</p>".html_safe }
          body
        end
      end

      def heading_mark
        render(Admin::Ui::SettingsCardComponent.new(heading_id: "preview-order", heading: "Languages", icon: :translations, family: :text)) do |card|
          card.with_heading_mark { "<span class=\"admin-save-bar-heading-mark\"><span class=\"sr-only\">Order changed</span></span>".html_safe }
          body
        end
      end

      private

      def body = "<div class=\"p-4 text-sm text-ink\">The card's fields.</div>".html_safe
    end
  end
end
