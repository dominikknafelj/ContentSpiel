# Who has a record open (presence spec §5): a page, a post or a library image.
# A throwaway row per person, record and browser tab (`Presence::Mark`) that
# the tab keeps fresh while it is open, a query that answers who is on a
# record without the viewer (`Presence::Roster`), a channel the tab arrives
# on (`Presence::Channel`) and a job that sweeps what nobody keeps fresh
# (`Presence::Sweep`).
#
# THE NUMBERS. The tab beats every 30 seconds and is away after 5 minutes
# without input (both the tab's script). A row not refreshed for STALE_AFTER
# is ignored by EVERY read, whatever the sweep has or has not deleted: a
# crashed tab or a dropped network sends no "leave", and nobody may be shown
# as here for longer than that. It is 150 seconds, not the spec's 60,
# because browsers throttle timers in a tab that has been hidden for a while
# (Chrome: to about one run a minute after five minutes hidden), and a hidden
# tab is exactly an away person whose 30-second beat then arrives every 60
# seconds or so: two throttled beats and some slack. The sweep only keeps the
# table small, so it waits much longer than that (SWEEP_AFTER).
#
# PRESENCE IS NOT CONTENT. It is the one write that is not an
# `ApplicationService` (`CLAUDE.md`): a channel writes and deletes its own
# rows, nobody asks for it by name, and it is gone within 150 seconds of the
# tab's last word (STALE_AFTER). It is never
# audited, never touches the record it is on and never moves the public
# content version. It does not know notes, nor notes it.
module Presence
  STALE_AFTER = 150.seconds
  # How often the record's script sends its keep-alive. The server renders it
  # into the script's `beat` value, so this is the one source; the relation
  # that matters (STALE_AFTER >= 4 * BEAT_EVERY) is `test/models/presence_test.rb`.
  BEAT_EVERY = 30.seconds
  # How many ids one `GET presence/here` answers for, and how many the lists'
  # script asks about at once (rendered into its `chunk` value where the list
  # is drawn). More ids in a request are dropped by the server.
  HERE_IDS = 500
  SWEEP_AFTER = 5.minutes
  STATES = %w[here away].freeze
end
