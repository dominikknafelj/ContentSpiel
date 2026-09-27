module Admin
  # CS Studio's root (cs-studio spec §4.1). A placeholder until Task 3 wires
  # the Pages module (and its tree column) up as the actual home -- for now
  # this is just the shell (modules column) around an empty content frame,
  # so signing in has somewhere to land.
  class HomeController < BaseController
    def show
    end
  end
end
