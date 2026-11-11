require "test_helper"

class SessionDeviceTest < ActiveSupport::TestCase
  FIREFOX_MAC = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7; rv:130.0) Gecko/20100101 Firefox/130.0".freeze
  CHROME_WINDOWS = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36".freeze
  SAFARI_IPHONE = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1".freeze
  CHROME_ANDROID = "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36".freeze
  CHROME_CHROMEOS = "Mozilla/5.0 (X11; CrOS x86_64 14541.0.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36".freeze
  FIREFOX_LINUX = "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0".freeze
  GOOGLEBOT = "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)".freeze

  test "Firefox on macOS" do
    assert_equal [ "device", { browser: "Firefox", os: "macOS" } ], SessionDevice.new(FIREFOX_MAC).key_and_values
  end

  test "Chrome on Windows" do
    assert_equal [ "device", { browser: "Chrome", os: "Windows" } ], SessionDevice.new(CHROME_WINDOWS).key_and_values
  end

  test "Edge is Edge, not Chrome, on desktop and on a phone" do
    desktop = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 Edg/126.0.2592.81"
    android = "Mozilla/5.0 (Linux; Android 10; HD1913) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36 EdgA/126.0.2592.80"
    ios = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 EdgiOS/126.2592.82 Mobile/15E148 Safari/605.1.15"
    assert_equal [ "device", { browser: "Edge", os: "Windows" } ], SessionDevice.new(desktop).key_and_values
    assert_equal [ "device", { browser: "Edge", os: "Android" } ], SessionDevice.new(android).key_and_values
    assert_equal [ "device", { browser: "Edge", os: "iOS" } ], SessionDevice.new(ios).key_and_values
  end

  test "Safari on an iPhone is iOS" do
    device = SessionDevice.new(SAFARI_IPHONE)
    assert_equal "Safari", device.browser
    assert_equal "iOS", device.os
  end

  test "Chrome on Android" do
    assert_equal [ "device", { browser: "Chrome", os: "Android" } ], SessionDevice.new(CHROME_ANDROID).key_and_values
  end

  test "ChromeOS and Linux" do
    assert_equal "ChromeOS", SessionDevice.new(CHROME_CHROMEOS).os
    assert_equal "Linux", SessionDevice.new(FIREFOX_LINUX).os
  end

  test "a product that is not a browser shows no browser name" do
    device = SessionDevice.new("curl/8.4.0")
    assert_nil device.browser
    assert_equal [ "unknown_device", {} ], device.key_and_values
  end

  test "a bot is an unknown device" do
    assert_equal [ "unknown_device", {} ], SessionDevice.new(GOOGLEBOT).key_and_values
  end

  test "a browser without a system known by name is browser only" do
    device = SessionDevice.new("Mozilla/5.0 (X11; FreeBSD amd64; rv:130.0) Gecko/20100101 Firefox/130.0")
    assert_equal [ "browser_only", { browser: "Firefox" } ], device.key_and_values
  end

  test "a system without a browser name says only the system" do
    device = SessionDevice.allocate
    device.instance_variable_set(:@os, "Android")
    assert_equal [ "os_only", { os: "Android" } ], device.key_and_values
  end

  test "nil and an empty string are unknown" do
    assert_equal [ "unknown_device", {} ], SessionDevice.new(nil).key_and_values
    assert_equal [ "unknown_device", {} ], SessionDevice.new("").key_and_values
  end

  test "a string over the length limit is unknown and is not parsed" do
    junk = "Mozilla/5.0 (Macintosh) Firefox/130.0 " + ("x" * 1000)
    assert_equal [ "unknown_device", {} ], SessionDevice.new(junk).key_and_values
  end

  test "junk does not raise" do
    assert_equal [ "unknown_device", {} ], SessionDevice.new("((((;;;)))) \u0000 //").key_and_values
  end
end
