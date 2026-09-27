module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def find_session_by_cookie
      Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to admin_sign_in_path
    end

    # The public site needs no authentication of its own (PagesController
    # opts out via allow_unauthenticated_access), so the only way anyone
    # reaches here at all is by signing in to manage content -- a session
    # cookie recorded a page to return to only when `request_authentication`
    # redirected here from one; without that, `admin_root_url` would send a
    # fresh admin login back out to the public site instead of into CS
    # Studio (cs-studio spec §3 -- CS Studio, not Avo, is the landing page).
    def after_authentication_url
      session.delete(:return_to_after_authenticating) || admin_root_url
    end

    def start_new_session_for(user)
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.session = session
        cookies.signed.permanent[:session_id] = { value: session.id, httponly: true, same_site: :lax }
      end
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
