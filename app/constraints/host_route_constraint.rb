# Which host a route answers on, when CS Studio has a host of its own
# (`ADMIN_HOST`, `SiteAddress.admin`). Without one, both match every request
# and one host serves the backend and the site.
#
# Read per request, never while routes load: the address is not fixed when
# the routes are drawn in a test, and a route drawn with a host baked in
# could not be switched by `with_admin_address`.
#
# `Site` is "not the admin host", not "the public host": `config.hosts`
# (`HostSettings.apply`) already refuses every name but the two, so the only
# host the site must not answer on is the admin one. A host is compared as
# `config.hosts` compares it: case-insensitively, the port ignored
# (`request.host` carries none).
#
# A request on the wrong host is not routed here: on the public host a
# backend path falls through to the page catch-all, and on the admin host a
# page path finds no route; either way the public 404, never a redirect,
# which would name the other host. `/up` (the proxy asks it on either name) and
# Active Storage's routes (a page on the site and an image in CS Studio embed
# the same files) carry neither constraint.
module HostRouteConstraint
  # The routes under /<ADMIN_PATH>/: on the admin host alone.
  module Backend
    def self.matches?(request)
      admin = SiteAddress.admin
      !admin.configured? || request.host.casecmp?(admin.host)
    end
  end

  # The public site's pages and form sends: on every host but the admin one.
  module Site
    def self.matches?(request)
      admin = SiteAddress.admin
      !admin.configured? || !request.host.casecmp?(admin.host)
    end
  end
end
