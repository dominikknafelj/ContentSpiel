# NO SESSION, NO TOKEN AND NO COOKIE, AS A WALL: no CSRF token on a public
# page, which is the same cookie-less answer for every visitor
# (`docs/reference/theming.md`). It was `PublicController`'s own until forms
# gave a visitor a second door, the endpoint a form posts to
# (`FormSendsController`), which is no `PublicController` (it is never
# cached and draws no theme) and must leave the browser's cookies exactly as
# the public pages do. Both include this, FIRST in the class, so its
# `around_action` is around every callback and action of the class and of
# its subclasses, one that answers early included (`leave_no_cookie` below
# says what it does and what it does not hold).
#
# The first line of `PublicController` was a convention while every public
# template was the CMS's own. A theme's templates are not: a `form_with`
# or a `button_to` in a theme's footer, `csrf_meta_tags` in its head or a
# `form_authenticity_token` anywhere asks Rails for the token, Rails reads
# the session to mint it, and the response, which says
# `Cache-Control: public`, leaves with a `Set-Cookie`. So:
#
# - the session of a request here is never committed (`:skip`, which the
#   session middleware asks before it writes the cookie), whatever a
#   template read or wrote in it;
# - `protect_against_forgery?` answers false, which is what
#   `csrf_meta_tags` and every form helper ask before they print a token;
# - `form_authenticity_token`, which mints one without asking, answers nil.
#
# Nothing public needs either: every public page route is a GET
# (`config/routes.rb`: `pages#show` only), and the one POST, a visitor's
# send of a form (`form_sends#create`), takes no token by design (its
# controller says why). No action reads the session. A theme's GET form (a
# search box) works as before, and a form that posts to another service
# posts without a token of this application, which that service could not
# have checked anyway. `PreviewController` includes none of this: it is
# signed in, private and never cached. `Theme::Check` refuses the same
# words in a theme's template with a message that says why; this is what
# holds for a spelling it does not see
# (`test/integration/theme_pages_test.rb`: "a public page drawn under a
# theme sets no cookie and carries no token…";
# `test/integration/form_sends_test.rb`: "a signed-in editor's cookies are
# neither changed nor dropped by a send").
module Cookieless
  extend ActiveSupport::Concern

  included do
    around_action :leave_no_cookie
    before_action { request.session_options[:skip] = true }
  end

  private

  # THE COOKIE JAR IS NOT THE SESSION. `cookies[:seen] = "1"` in a theme's
  # template (a consent banner, an A/B flag: honest mistakes), and
  # `cookies.signed`, `.encrypted`, `.permanent` and `cookies.delete`, are
  # kept in the request's jar and written into the response by
  # `ActionDispatch::Cookies`, a middleware of its own that never asks the
  # session's `:skip`. A public page says `Cache-Control: public`, so a
  # shared cache that keeps it would hand one visitor's `Set-Cookie` to the
  # next. So, once the action and its templates are done (the layout is
  # rendered inside the action), and also when a callback answered early:
  #
  # - the request gets a NEW jar, built from the cookies the browser sent
  #   and holding no write and no delete, which is the one the middleware
  #   then finds and writes nothing from (actionpack 8.1.4,
  #   `ActionDispatch::Cookies#call`: `request.cookie_jar.write(response)`).
  #   Nothing is sent to delete a cookie either: a signed-in editor's
  #   cookies are neither changed nor taken away by reading a public page
  #   or sending a form;
  # - a `Set-Cookie` put on the response by hand (`response.set_cookie`,
  #   `response.headers["Set-Cookie"] = …`) is taken off.
  #
  # A write to the flash is a write to the session and goes with it
  # (`:skip`, above).
  #
  # WHAT THIS HOLDS: no `Set-Cookie` leaves a response of a controller that
  # includes this, or of a subclass, whatever a template calls in the view.
  # What it does not: an action that raises is answered by the exceptions
  # application, outside the controller (the cookie middleware writes
  # nothing then: it is passed by the exception), and a cookie set by a
  # script in the browser (`document.cookie`) is the browser's and never
  # this response's. `Theme::Check` refuses a cookie write in a theme's
  # template at the boot with a sentence that says why; this is what holds
  # for the spelling it does not see (`test/integration/theme_pages_test.rb`:
  # "a public page drawn under a theme sets no cookie and carries no
  # token…", "a signed-in editor reads a public page under a grasping theme
  # and is still signed in…").
  def leave_no_cookie
    yield
  ensure
    request.cookie_jar = ActionDispatch::Cookies::CookieJar.build(request, request.cookies) if request.have_cookie_jar?
    response.delete_header("Set-Cookie")
  end

  def protect_against_forgery? = false

  def form_authenticity_token(**) = nil
end
