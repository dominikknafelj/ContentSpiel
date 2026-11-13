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
      Session.from_cookies(cookies)
    end

    # Fix (final-fixes round, finding 4): only a GET is safe to remember
    # verbatim -- a PATCH/POST/DELETE's own URL (an autosave endpoint, a
    # reorder, a publish action, ...) often has no GET route at all (a block
    # card's `.../content_blocks/:id`, the tree's own `/tree`), so replaying
    # it after signing back in would hit a routing error instead of landing
    # anywhere useful. The page an editor was actually looking at when that
    # request fired is the *referer*, not the request's own URL, so that's
    # what a non-GET falls back to instead -- and when even that's missing
    # (no referer header at all), `after_authentication_url`'s own fallback
    # to `admin_root_url` already covers a blank `session[:return_to_
    # after_authenticating]` needing no special-casing here.
    def request_authentication
      # `request.get? || request.head?`, not `get?` alone: Rails routes a
      # `HEAD` request through the exact same `get` route a `GET` would hit
      # (and `ActionDispatch::Http::Cache::Request` answers it with no
      # body) -- `request.get?` itself returns `false` for one regardless
      # (Brakeman's own `VerbConfusion` check flags exactly this), which
      # would otherwise fall through to the non-GET branch below and
      # remember a `HEAD` request's *referer* instead of the URL it was
      # actually for.
      session[:return_to_after_authenticating] = (request.get? || request.head?) ? request.url : request.referer
      return load_whole_page if turbo_get?

      forget_ended_session
      redirect_to admin_sign_in_path
    end

    # A page Turbo may not draw (`turbo-visit-control: reload`).
    RELOAD_PAGE = '<!DOCTYPE html><html><head><meta name="turbo-visit-control" content="reload"></head><body></body></html>'.html_safe.freeze

    # Turbo's own GET (a Drive visit, a frame's load, a hover's prefetch:
    # `X-Turbo-Request-Id`), or a script's GET for a frame (`Turbo-Frame`),
    # is not redirected. The redirect would be followed inside the fetch,
    # which draws the sign-in page and spends "Your session ended." there;
    # wherever the sign-in page asks to be loaded whole (on a site with the
    # bot check's keys) Turbo then loads it again, without the notice, and a
    # prefetch spends it before the click. Answered with a page Turbo may
    # not draw, Turbo loads the address it asked for whole instead (a
    # frame's response is visited, and a visit of an undrawable page
    # reloads), and that load is a browser's own: it is told, the cookie is
    # cleared and it goes to the sign-in page. Nothing here is spent or
    # cleared, so a script's frame fetch (a live refresh, which finds no
    # frame in this page, as it found none in the sign-in page) leaves the
    # notice for the next page.
    def turbo_get?
      (request.get? || request.head?) && (turbo_frame_request? || request.headers["X-Turbo-Request-Id"].present?)
    end

    def load_whole_page
      render html: RELOAD_PAGE, layout: false
    end

    # A signed `session_id` that `Session.from_cookies` did not resolve names
    # a session that is gone (ended elsewhere, or expired): only that browser
    # is told so, once, by a flash the sign-in page reads, and the cookie is
    # cleared so the next visit is a plain sign-in. A browser with no cookie
    # and a forged one (`cookies.signed` reads nil) are told nothing, and the
    # sentence names no account.
    #
    # Only a page the person asked for (a GET or HEAD for HTML that is no
    # XHR) is told, and only it clears the cookie. A write or a script's
    # fetch (an autosave, a stream, JSON) that meets the gone session first
    # leaves both: its redirect is followed inside the fetch, where the
    # sign-in page drawn would spend the flash unseen, and a cookie cleared
    # there would leave the person's next page nothing to name, so they
    # would get a plain sign-in. Kept, the cookie still names a row that is
    # gone (ids are never reused), and that next page says it. A script's
    # GET for HTML with no `Turbo-Frame` header (the live editing refresh)
    # still counts as a page: nothing in the request tells it from a visit.
    # (Turbo's own GET and a frame's never come here: `turbo_get?`.)
    def forget_ended_session
      return if cookies.signed[:session_id].blank? || !page_request?

      cookies.delete(:session_id)
      flash[:session_ended] = true
    end

    def page_request?
      (request.get? || request.head?) && !request.xhr? && request.format.html?
    end

    # The public site needs no authentication of its own (PagesController
    # opts out via allow_unauthenticated_access), so the only way anyone
    # reaches here at all is by signing in to manage content -- a session
    # cookie recorded a page to return to only when `request_authentication`
    # redirected here from one; without that, `admin_root_url` would send a
    # fresh admin login back out to the public site instead of into CS
    # Studio (cs-studio spec §3 -- CS Studio is the landing page).
    def after_authentication_url
      session.delete(:return_to_after_authenticating) || admin_root_url
    end

    # The cookie ends with the session, never later: it is not permanent.
    # The passkey policy is read here, once per session (`enrolment_due`),
    # so a policy changed later reaches a person at their next sign-in; the
    # policy it was read as is `auth.policy` on the request's span (a
    # passkey sign-in has no `auth.sign_in`, and a password's has closed).
    def start_new_session_for(user, method: "password")
      policy = Passkeys::Policy.current
      Telemetry.record(OpenTelemetry::Trace.current_span, "auth.policy" => policy.name)
      Session.start(user: user, method: method, user_agent: request.user_agent, ip_address: request.remote_ip,
        enrolment_due: policy.enrolment_due?(user, method: method)).tap do |session|
        Current.session = session
        cookies.signed[:session_id] = { value: session.id, httponly: true, same_site: :lax, expires: session.expires_at }
      end
    end

    # Every passkey challenge's cookie goes with the session: a challenge
    # is the signed-out person's ceremony, never the next person's.
    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
      PasskeyChallenges.cookie_names.each { |name| cookies.delete(name, path: "/") }
    end
end
