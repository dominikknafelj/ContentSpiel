module Admin
  module Ui
    # `Admin::Ui::InsecureNoticeComponent`, drawn as production draws it over
    # plain HTTP: the preview hands over a plain request and `production: true`.
    class InsecureNoticeComponentPreview < ViewComponent::Preview
      def rest
        render Admin::Ui::InsecureNoticeComponent.new(request: ActionDispatch::TestRequest.create("HTTPS" => "off"), production: true)
      end
    end
  end
end
