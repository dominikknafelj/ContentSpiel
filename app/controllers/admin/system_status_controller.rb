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
    end
  end
end
