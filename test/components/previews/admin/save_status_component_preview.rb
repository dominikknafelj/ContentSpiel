module Admin
  # `Admin::SaveStatusComponent` (cs-studio spec §6.1): every autosave state,
  # exact wording from Global Constraints.
  class SaveStatusComponentPreview < ViewComponent::Preview
    def idle
      render Admin::SaveStatusComponent.new(id: "save-status-idle", state: :idle)
    end

    def saving
      render Admin::SaveStatusComponent.new(id: "save-status-saving", state: :saving)
    end

    def saved
      render Admin::SaveStatusComponent.new(id: "save-status-saved", state: :saved, at: Time.current)
    end

    def error
      render Admin::SaveStatusComponent.new(id: "save-status-error", state: :error, count: 2)
    end

    def retrying
      render Admin::SaveStatusComponent.new(id: "save-status-retrying", state: :retrying)
    end

    def offline
      render Admin::SaveStatusComponent.new(id: "save-status-offline", state: :offline)
    end

    def stale
      render Admin::SaveStatusComponent.new(id: "save-status-stale", state: :stale)
    end
  end
end
