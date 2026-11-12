module Admin
  # The streams that show a new set of recovery codes once on Your account
  # (`Admin::PasskeysController#create` after a first passkey,
  # `Admin::RecoveryCodesController#create`): the codes dialog drawn into the
  # screen's slot (SLOT_ID), where it opens by itself
  # (`Admin::Ui::RecoveryCodesComponent`, `frame: :dialog`), and the page
  # marked `turbo-cache-control: no-cache`, so Turbo keeps no snapshot of a
  # page that held the codes. A second set drawn into the slot replaces the
  # first. `builder` is the answer's stream builder.
  module AccountRecoveryCodes
    SLOT_ID = "account-recovery-codes".freeze
    CODES_ID = "new-recovery-codes".freeze

    def self.streams(builder, codes)
      [
        builder.update(SLOT_ID, Admin::Ui::RecoveryCodesComponent.new(codes: codes, frame: :dialog, id: CODES_ID)),
        builder.append_all("head", ActionController::Base.helpers.tag.meta(name: "turbo-cache-control", content: "no-cache"))
      ]
    end
  end
end
