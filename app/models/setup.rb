# The first-run setup wizard's state (design spec 2026-09-26 §3). Setup is
# "required" until SiteSetting#setup_completed_at is set -- not while
# `User.none?`, because the wizard creates the admin in step 3 and would
# otherwise lock itself out of every later step.
module Setup
  # Once setup is done it stays done, so this stops querying after the first
  # "no" (spec §6.1) -- every request passes through
  # Setup::RedirectConstraint. SiteSetting resets the latch after any commit,
  # which covers tests that un-complete setup, and a console session that does.
  def self.required?
    return false if @completed

    completed = SiteSetting.where.not(setup_completed_at: nil).exists?
    @completed = true if completed
    !completed
  end

  def self.reset!
    @completed = nil
  end

  # Finishing the wizard: the homepage always exists afterwards, and setup
  # stops being required. Safe to call twice.
  def self.complete!
    SiteSetting.transaction do
      setting = Current.site
      StarterContent.ensure_home!(locale: setting.default_locale)
      setting.update!(setup_completed_at: Time.current) if setting.setup_completed_at.nil?
    end
  end
end
