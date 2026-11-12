module Admin
  module Ui
    # `Admin::Ui::RecoveryCodesComponent` in its two frames: in a dialog (the
    # dialog is drawn closed, since Lookbook's layout lacks the admin script)
    # and on a page of its own, with Done as a link.
    class RecoveryCodesComponentPreview < ViewComponent::Preview
      CODES = %w[k3f9-x2mq 7hd2-p8vz m4qa-9tzc w6ne-h3ry b8ux-d5kj r2cv-n7ps t9gy-a4wm e5zh-j6bq c7lp-u3xd f2sk-v8nt].freeze

      def dialog
        render Admin::Ui::RecoveryCodesComponent.new(codes: CODES, frame: :dialog, id: "recovery-codes-preview-dialog")
      end

      def page
        render Admin::Ui::RecoveryCodesComponent.new(codes: CODES, frame: :page, done_href: "/cs-studio", id: "recovery-codes-preview-page")
      end
    end
  end
end
