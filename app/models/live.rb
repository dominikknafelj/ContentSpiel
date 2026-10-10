# Live updates (presence spec §4.2): what the server pushes to open CS Studio
# tabs, and the base of a channel on one record. Notes and presence are its two
# users; each says what it has to say through `Live::Signals` (the one sender)
# and subscribes through a subclass of `Live::RecordChannel`. The browser's
# half -- the one connection every feature shares -- is `app/javascript/live/`.
#
# This is a top-level name, so `Admin::Live` may never be defined (it would
# shadow this module for every bare `Live::` inside `module Admin`;
# `test/lib/admin_namespace_shadow_test.rb` derives that).
module Live
end
