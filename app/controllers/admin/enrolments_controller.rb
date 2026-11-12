module Admin
  # Enrolment: the page a person the passkey policy covered at sign-in, who
  # holds no passkey, is sent to from every CS Studio page and the preview
  # (`Admin::PasskeyEnrolment`), on the product layout's panel. It asks for
  # the passkey's name and adds it through the Passkeys card's endpoints
  # (`admin--passkeys--register`, `from: "enrolment"`), behind Confirm it's
  # you once the sign-in is more than Session::CONFIRM_WINDOW old; the codes
  # follow in place of the page (`Admin::PasskeysController#create`). Sign out
  # stays open.
  #
  # A session with nothing due, or a request with no relying party (where no
  # passkey can be made and the gate holds nothing), is sent to the
  # dashboard.
  class EnrolmentsController < BaseController
    include PasskeyChallenges

    # The page's region, which the codes replace.
    ID = "enrolment".freeze

    layout "product"
    skip_before_action :require_passkey_enrolment

    def show
      return redirect_to(admin_root_path) unless Current.session.enrolment_due? && passkey_relying_party

      # The policy now, for the lead's words; the session was held by the
      # one read at sign-in, and only `everyone` says "everyone".
      @lead = Passkeys::Policy.current.name == "everyone" ? "everyone" : "owners_and_admins"
    end
  end
end
