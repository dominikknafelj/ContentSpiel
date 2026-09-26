# The first-run setup wizard's state (design spec 2026-09-26 §3). Setup is
# "required" until SiteSetting#setup_completed_at is set -- not while
# `User.none?`, because the wizard creates the admin in step 3 and would
# otherwise lock itself out of every later step.
module Setup
  def self.required?
    !SiteSetting.where.not(setup_completed_at: nil).exists?
  end
end
