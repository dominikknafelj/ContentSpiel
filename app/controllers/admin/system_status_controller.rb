module Admin
  # System status (design spec §6.1): the same read-only checks the
  # setup wizard runs (`Setup::SystemCheck`), re-run on every request --
  # "Run again" is just a link back here. The checks are told how this
  # request came (`request.ssl?`), which is what the "HTTPS" check reports,
  # and whom it is counted as (`request.remote_ip` beside Cloudflare's
  # `CF-Connecting-IP`), which is what "Visitor address" reports.
  class SystemStatusController < BaseController
    before_action -> { require_permission("system_status.view") }

    def show
      @results = Setup::SystemCheck.run(request_ssl: request.ssl?, reset_link_from_request: PasswordsMailer.request_origin_used?,
        remote_ip: request.remote_ip, cf_connecting_ip: request.headers[Setup::SystemCheck::CLOUDFLARE_HEADER],
        mail_settings_link: can?("settings.manage"), image_settings_link: can?("settings.manage"),
        forms_link: holds_any?(%w[forms.manage form_submissions.view]))
      @content_results = content_results
      @alerts = ::Alerts::Alert.recent
      @mail_blocked_by = ::Alerts::Mailing.blocked_by
    end

    private

    # The "Content" card's rows: what the site's content asks of someone, which
    # is not a check of the host. They are `Setup::SystemCheck::Result`s so the
    # same row draws them, but never `Setup::SystemCheck`'s: the wizard and the
    # summary's "n of m checks passed" do not count them. Only a viewer who can
    # draw a diagram (`pages.edit`) sees the card, and only then is the count
    # asked.
    def content_results
      return [] unless can?("pages.edit")

      count = ::Diagrams::ToDraw.new(actor: Current.actor).count
      label = t("admin.system_status.show.content.diagrams.label")
      return [ Setup::SystemCheck::Result.new(label:, status: :ok, message: t("admin.system_status.show.content.diagrams.ok")) ] if count.zero?

      [ Setup::SystemCheck::Result.new(label:, status: :warning, link: :diagram_drawings,
        message: t("admin.system_status.show.content.diagrams.to_draw", count: count)) ]
    end
  end
end
