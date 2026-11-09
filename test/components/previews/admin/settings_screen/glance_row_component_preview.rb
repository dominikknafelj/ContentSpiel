module Admin
  module SettingsScreen
    # `GlanceRowComponent`, one row of the rail per state. The AI and mail
    # states are drawn from an unsaved copy of the site row, never from a
    # real key or a real login.
    class GlanceRowComponentPreview < ViewComponent::Preview
      def languages
        render row("languages")
      end

      def ai_off
        render row("ai", site: site)
      end

      def ai_no_key
        render row("ai", site: site(ai_provider: "anthropic"))
      end

      def ai_key_saved
        render row("ai", site: site(ai_provider: "anthropic", key: "preview-key"))
      end

      def ai_connected
        render row("ai", site: site(ai_provider: "anthropic", key: "preview-key"), ai_result: :connected)
      end

      def ai_not_connected
        render row("ai", site: site(ai_provider: "anthropic", key: "preview-key"), ai_result: :failed)
      end

      def mail_not_set_up
        render row("mail", site: site)
      end

      def mail_saved_not_tested
        render row("mail", site: site(mail_server: "smtp.example.test", mail_port: 587, mail_security: "starttls", mail_sender_address: "no-reply@example.test"))
      end

      def images_ready
        render row("images", progress: { total: 20, made: 20, failed: 0 })
      end

      def images_waiting_and_failed
        render row("images", progress: { total: 20, made: 6, failed: 2 })
      end

      def images_none
        render row("images", progress: { total: 0, made: 0, failed: 0 })
      end

      private

      def row(id, site: SiteSetting.instance, progress: { total: 0, made: 0, failed: 0 }, ai_result: nil)
        Admin::SettingsScreen::GlanceRowComponent.new(section: SettingsSections.find(id), site_setting: site, mail_settings: MailSettings.current(site, env: {}),
          images_progress: progress, locales: Locales.enabled, default: Locales.default, ai_result: ai_result)
      end

      def site(key: nil, **columns)
        SiteSetting.new(time_zone: "UTC", **columns).tap { |site| site.ai_api_key = key if key }
      end
    end
  end
end
