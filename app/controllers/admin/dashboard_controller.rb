module Admin
  # CS Studio's start page (dashboard spec §3-§4, Task 2): "Your work", "On
  # the site" and quick create. Open to every signed-in user -- its own
  # `MODULES` entry (`BaseController::MODULES`) has `permission: nil`, so a
  # user whose groups hold no grants at all (nothing to read, nothing to
  # write) still lands here instead of a 403 the moment they sign in; each
  # list it shows is read-scoped (`AccessControl.scope`), so it simply comes
  # back empty for them, the same way every other admin list already does.
  class DashboardController < BaseController
    def show
    end
  end
end
