module Admin
  # System status (design spec §6.1, Task 9): the same read-only checks the
  # setup wizard runs (`Setup::SystemCheck`), re-run on every request --
  # "Run again" is just a link back here. The checks are told how this
  # request came (`request.ssl?`), which is what the "HTTPS" check reports.
  class SystemStatusController < BaseController
    before_action -> { require_permission("system_status.view") }

    def show
      @results = Setup::SystemCheck.run(request_ssl: request.ssl?, reset_link_from_request: PasswordsMailer.request_origin_used?)
    end
  end
end
