# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

# Deliberately narrow (structure review #37): this backstops
# RichTextScrubber (app/sanitizers/rich_text_scrubber.rb) -- even if a rogue
# iframe ever slipped past that scrubber, the browser itself would still
# refuse to load a frame from anywhere but this app or youtube-nocookie.com.
# `object_src`/`base_uri` close the two other classic injection vectors
# (a plugin embed, a <base> tag rewriting relative URLs) at effectively no
# cost to anything the app already does.
#
# script-src/style-src/default-src are intentionally NOT set here: import
# maps and inline scripts throughout this app all assume an unconstrained
# policy today, and locking those down is a separate, larger
# roadmap item -- setting them now would break the app, not harden it. No
# nonce generator is configured for the same reason: nothing here needs one
# yet.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.frame_src  :self, "https://www.youtube-nocookie.com"
    policy.object_src :none
    policy.base_uri   :self
  end
end
