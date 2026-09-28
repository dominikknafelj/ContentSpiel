module Admin
  # System status (design spec §6.1, Task 9): the same read-only checks the
  # setup wizard runs (`Setup::SystemCheck`), re-run on every request --
  # "Run again" is just a link back here.
  class SystemStatusController < BaseController
    def show
      @results = Setup::SystemCheck.run
    end
  end
end
