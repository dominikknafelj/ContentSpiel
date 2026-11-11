# THE DEVICE A SESSION WAS MADE FROM, read from its user agent string: a
# browser's name and a person's name for the system ("Firefox", "macOS"),
# for the Sessions card on Your account. A value object: it reads no locale
# (`#key_and_values` answers the key under
# `admin.components.account_screen.sessions_card` and its interpolations,
# and the component says it in words).
#
# A user agent is what a client chose to send, so it is read as untrusted:
# a string over MAX_LENGTH is not parsed at all, a bot or a product the gem
# does not know as a browser (curl, a library) shows no browser name, and a
# system the gem names in its own way ("OS X 10.15.7", "Windows 10") is
# reduced to the short name or to nothing. Nothing here raises.
class SessionDevice
  MAX_LENGTH = 512

  # The gem's platform, in a person's words. A platform the gem names
  # otherwise (X11 for any desktop Linux, a bare "Linux") is matched on its
  # operating system's name below.
  PLATFORMS = {
    "Macintosh" => "macOS",
    "Windows" => "Windows",
    "iPhone" => "iOS",
    "iPad" => "iOS",
    "iPod" => "iOS",
    "Android" => "Android",
    "ChromeOS" => "ChromeOS"
  }.freeze

  EDGE_TOKEN = %r{\bEdg(?:A|iOS)?/\d}

  attr_reader :browser, :os

  def initialize(user_agent)
    @browser, @os = read(user_agent)
  end

  # The locale key under `admin.components.account_screen.sessions_card` and
  # what it interpolates.
  def key_and_values
    if browser && os
      [ "device", { browser: browser, os: os } ]
    elsif browser
      [ "browser_only", { browser: browser } ]
    elsif os
      [ "os_only", { os: os } ]
    else
      [ "unknown_device", {} ]
    end
  end

  private

  def read(user_agent)
    return [ nil, nil ] unless user_agent.is_a?(String) && user_agent.present? && user_agent.length <= MAX_LENGTH

    agent = UserAgent.parse(user_agent)
    return [ nil, nil ] if agent.bot?

    # The gem answers a product it has no class for with its base class: not a browser.
    browser = agent.class == UserAgent::Browsers::Base ? nil : agent.browser.presence
    # The gem reads Edge (its "Edg/", "EdgA/" and "EdgiOS/" tokens) as Chrome or Safari.
    browser = "Edge" if browser && EDGE_TOKEN.match?(user_agent)
    [ browser, os_of(agent) ]
  rescue StandardError
    [ nil, nil ]
  end

  def os_of(agent)
    PLATFORMS[agent.platform.to_s] || (agent.os.to_s.match?(/\ALinux/) ? "Linux" : nil)
  end
end
