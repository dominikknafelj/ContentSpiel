# Backups, the restore runbook and the drill

> Describes: `bin/backup` with `lib/content_spiel/backup.rb` (`ContentSpiel::Backup`) and `lib/content_spiel/backup/` (`Failure`, `Status`, `RunningVersion`, `Runner`), `lib/content_spiel/backup_accessory.rb` (`ContentSpiel::BackupAccessory`, the accessory's block and secrets), the backup parts of `lib/content_spiel/upgrade.rb` (`BACKUP_RUN`, `BACKUP_REBOOT`, the offer of the block) and `lib/content_spiel/site_generator.rb` (`backup_accessory`, `backup_secrets`), the site template's `lib/site_template/config/deploy.yml.tt` (the accessory, commented), `lib/site_template/kamal/secrets.example.tt` (its three secrets), `lib/site_template/README.md.tt` (step 4.4, Backups, and step 5's backup) and `lib/site_template/docs/restore-drills/TEMPLATE.md.tt`, the `Dockerfile`'s `restic` and `postgresql-client-17`, `.github/workflows/image.yml`'s steps "The image's backup tools" and "Back up and restore the booted site", the Backups row of `app/models/setup/system_check.rb` (`#backups`, `FRESH_BACKUP`, `BACKUPS_DOCS`, `BACKUP_REBOOT_COMMAND`) with `admin.system_status.backups.*` in `config/locales/admin/system_status.en.yml`, `app/queries/alerts/backup_rule.rb` (`Alerts::BackupRule`, the `backup_stale` alert, whose part of the alerts is `docs/reference/alerting.md`, "Backups"), `PublicSite.after_restore!` in `app/models/public_site.rb` with `PublicSite::Version.jump_past!` in `app/models/public_site/version.rb` and the task `public_site:after_restore` in `lib/tasks/public_site.rake`, and the tests' `test/support/fake_backup_runner.rb`.

The design is `docs/superpowers/specs/2026-11-17-backups-design.md` (issue #175), with the plan's rulings in `docs/superpowers/plans/2026-11-17-backups.md`; this file says what was built. The variables are rows of `docs/reference/hosting.md`, "Every variable the code reads"; what the site template's CI job runs is `docs/reference/hosting.md`, "What the site template's CI job holds".

## What is backed up

Two things, which are everything a site needs to come back with its content, its accounts and its images:

- **The primary database**, `content_spiel_production`: pages, posts, blocks, published copies, people, groups, tokens, the audit log (its append-only trigger with it), the settings, the forms' submissions, the built-in search index and the content version's counter. Dumped with `pg_dump --format=custom`, which `pg_restore` reads table by table and which is compressed.
- **The files volume**, the folder mounted at `/rails/storage`: the library's images and their made widths, notes' files and everything else Active Storage keeps on the disk. The status folder `storage/backup/` is left out.

**Not** the cache, queue and cable databases (`content_spiel_production_cache`, `_queue`, `_cable`): they are rebuilt empty, and a queued job lost with them is acceptable (the recurring jobs come back from `config/recurring.yml`). Not a site's code or theme either: those are in the site's repository and its image.

## Recovery targets

- **RPO: 24 hours.** One backup a day; at most a day of changes is lost.
- **RTO: 2 hours** for a person following the runbook on a new server, with the destination's credentials at hand. The drill measures it; a drill above it is a finding.
- **Retention:** `restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune`.
- **Integrity:** `restic check --read-data-subset=n/12` once a month, n the month, so a year reads all the data once.

Point-in-time recovery (WAL archiving) is not built: a daily dump is the target (`docs/roadmap.md`).

## The accessory

A site from the template runs its backups in a Kamal accessory, `backup`, beside the database accessory on the site's own server. `contentspiel new` writes it into `config/deploy.yml` commented, at the end of `accessories:`, between two comment lines, `# The backup accessory` and `# End of the backup accessory` (`BackupAccessory::BEGIN_MARK`, `END_MARK`), and the README's step 4.4 turns it on. Commented, each line between the marks is `  # ` and the line without its first two spaces, so an editor's "toggle comment", which takes out `# `, gives back the uncommented block at its depth. `contentspiel upgrade` prints the same block, uncommented, to a site whose `deploy.yml` has no `backup:` line (`docs/reference/hosting.md`, "A site's version"); `BackupAccessory.block` is the one source of both.

- **The image is the CMS's at the site's pin**, `<ContentSpiel::IMAGE>:<%= pin %>` (the ERB at the top of every template-made `deploy.yml` reads `.contentspiel-version`), not the site's own image: a backup needs no theme, and the version is the one the site runs. Kamal gives an accessory one fixed image and `kamal deploy` does not reboot it, so after a deploy that moves the pin `kamal accessory reboot backup` moves the accessory along: `upgrade`'s next steps and the README's step 5 say so, and System status warns while the two differ. The backup made before an upgrade's deploy runs on the old version, which is right: it dumps the schema as that version left it.
- **`cmd: bin/backup schedule`**, one run a day at `BACKUP_HOUR`.
- **It yields to the website.** `options: cpus: 1` caps it at one CPU, and every tool of a run starts under `nice -n 19 ionice -c 3 -t` (the idle I/O class; `-t` runs the tool anyway on a host that refuses the class).
- **The whole files volume, read and write**, mounted where the web mounts it (`<name>_storage:/rails/storage`). The command reads all of it and writes one folder, `storage/backup/`, the status file's and the accessory's version file's ("The status file"), which the web container reads. The dump is written to the container's own disk (`/tmp/content_spiel_backup`, mode 0700) and removed after every run, whatever happened; the run lock is the file beside it, `/tmp/content_spiel_backup.lock`, on the same disk.
- **Its variables**, under `env:`: `PGHOST` (the database accessory, `<name>-db`), `BACKUP_SITE` (the service's name), `BACKUP_REPOSITORY` (`s3:https://<endpoint>/<bucket>/<name>`, two placeholders the README's step fills; they are not `<your-…>` ones on purpose, so the README's check for unfilled placeholders stays quiet for a site without backups), `AWS_DEFAULT_REGION` (`auto`), `BACKUP_HOUR` (commented, 3), and the secrets `POSTGRES_PASSWORD` (the database accessory's), `RESTIC_PASSWORD`, `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` (`BackupAccessory::SECRETS`, commented in `.kamal/secrets.example` with how to make each). **The web container gets none of them.** `PGUSER` is not set: `pg_dump` connects as `postgres`, the database accessory's superuser.
- **No telemetry.** The accessory sends no spans. Its log (`kamal accessory logs backup`) is the command's own lines: `[backup] next run at …`, `[backup] <step> started`, `[backup] <step> finished in Ns, <size>`, `[backup] failed at <step>: <reason>`, `[backup] finished in Ns: snapshot <id>`.

A site that is not deployed with the template's Kamal setup runs the same command wherever the image runs with the files volume at `/rails/storage`, the database reachable and the variables set.

## The command: `bin/backup`

Plain Ruby on the standard library (`ContentSpiel::Backup`): the accessory does not boot Rails. It takes one subcommand and refuses anything else with its usage and exit 2: `run`, `schedule`, `list` and `init` take no argument, `restore` exactly two. Its exit code is 0, or 1 for a failure.

- **`run`**: one backup now. The steps, each printed as it starts and ends:
  1. **dump**: `pg_dump --format=custom --no-password --dbname content_spiel_production` into the dump folder, with `PGHOST`, `PGUSER` (default `postgres`) and `PGPASSWORD` from `POSTGRES_PASSWORD`;
  2. **backup**: one `restic backup --json` snapshot of the dump folder and of `/rails/storage`, the status folder excluded, tagged `site=<BACKUP_SITE>` and `cms=<ContentSpiel::VERSION>`; the snapshot's id and size come from restic's summary line, and a run without one fails as `other`;
  3. **forget**: `restic forget` with the retention above and `--prune`;
  4. **check**, when it is due: `restic check --read-data-subset=<month>/12`. It is due when no check was ever recorded, when the last one failed, or when the last one was in an earlier calendar month (UTC): the first run of a month, or the run after a failed check. A failed check leaves the backup ok; its reason is recorded and the next run checks again.

  Then the status file, ok or failed. A run without `BACKUP_REPOSITORY` says backups are not configured and exits 0, writing nothing.

  **One run at a time.** A run takes a non-blocking `flock` on `/tmp/content_spiel_backup.lock` (`DUMP_DIR` + `LOCK_SUFFIX`, beside the dump folder, never in it or in the files volume) and holds it to its end. A run that finds it held prints `[backup] another backup is already running` on stderr, exits 1, starts no tool and writes no status, so a person's `kamal accessory exec backup --reuse "bin/backup run"` at the schedule's hour never shares the dump or the status with the scheduled run (whichever comes second is refused; the schedule's next try is the next day). The lock is the container's: `accessory exec` without `--reuse` starts a new container with its own `/tmp`, which this lock does not see, so every command here that runs beside the schedule carries `--reuse`.
- **`schedule`**: the accessory's long-running command, with no cron daemon. Configured, it first writes `storage/backup/accessory.json`, the version it runs ("The status file"); a write that fails is named on stderr by its class and the schedule goes on. It sleeps until the next `BACKUP_HOUR`:00 UTC (default 3; a value that is not a whole hour from 0 to 23 is named and the command exits 1), runs, and sleeps until the next day's. A failed run is not retried before the next day, so a broken destination fails once a day, never in a loop. The next run is counted from the later of now and the last run's hour, so a wall clock set back after a run gives no second run that day. Unconfigured, it says so once a day, runs nothing and writes nothing. A status file that cannot be written (a full disk) raises out of `schedule` and ends the container; Kamal starts an accessory with Docker's `--restart unless-stopped` (Kamal 2.12's default, which the template's block does not change), so it comes back and sleeps until the next day's hour, and the status file still shows the run before the one whose write failed (that run's snapshot is in the repository all the same).
- **`list`**: restic's `snapshots`. **`init`**: restic's `init`, a new repository at `BACKUP_REPOSITORY`, once per site. Both print restic's stdout with every secret and the repository (with or without a trailing slash) replaced by `[hidden]`, and never its stderr: a failure is its reason.
- **`restore SNAPSHOT DIR`**: a snapshot (its id, or `latest`, both narrowed to `BACKUP_SITE`'s snapshots) into DIR, an empty or new folder, as `DIR/database.dump` and `DIR/files/` (the files volume's content) and nothing else. It touches no database and no live volume; a failed restore leaves nothing behind in DIR.

**Fixed host and paths.** Every snapshot is taken with `--host <BACKUP_SITE>` and the same two absolute paths, and `forget` narrows to that host. restic groups snapshots by host and paths: a container's random hostname or a random dump folder would make each snapshot a group of its own, which `forget` keeps whole, and the bucket would grow forever. `restore` finds the dump in a snapshot by those same paths.

**What a tool is given.** A tool starts from its argv, never through a shell, with a closed stdin (a tool that would ask for a password fails at once instead of waiting forever), and with exactly the environment it needs and nothing else of the accessory's (`Runner`, `unsetenv_others`): a fixed `PATH` (`/usr/local/bin:/usr/bin:/bin`); `pg_dump` the three `PG*` values, restic `HOME` (its cache), `RESTIC_REPOSITORY`, `RESTIC_PASSWORD` and the three `AWS_*`. A value that is not secret is read stripped of surrounding spaces; a secret is used as given. A missing secret is named (its name, never a value) before any tool starts, and a run then records the reason the tool would have failed with: `POSTGRES_PASSWORD` as `database_unreachable`, `RESTIC_PASSWORD` as `wrong_password`, an AWS key (needed only for an `s3:` repository) as `destination_unreachable`.

**Never a tool's message.** restic and pg_dump can print a password, a key or the repository's address. `run` prints its own lines only, and a failure is one of five fixed reasons (`Failure::REASONS`), read from the tool's exit code and stderr (`Failure.classify`) and never stored: `destination_unreachable` (also a repository that does not exist yet, restic's exit 10), `wrong_password` (restic's exit 12 or its words), `database_unreachable` (pg_dump's connection words), `disk_full` (either tool) and `other`. A step that raises (a tool that cannot be started) is `other`, named on stderr by the exception's class alone.

**Signals.** `bin/backup` traps TERM and INT (as the container's PID 1 Ruby would ignore TERM, and Kamal's stop would wait out its timeout and kill the container mid-upload). A stop while `schedule` sleeps wakes the sleep (a pipe the trap writes to; a `Queue` would not wake from a trap) and the schedule ends with 0. A stop during a run sends TERM to the running tool; the run ends as failed with the reason `other`, whatever the tool said, no further step starts, the status is written, and the schedule ends with 143. A monthly check that a stop ended is no verdict on the data: it stays due.

## The status file

`<app root>/storage/backup/status.json`, `/rails/storage/backup/status.json` in the image (`ContentSpiel::Backup::Status`), written by the accessory after every run and read by the web container (System status, the alert). Its fields:

| Field | What |
|---|---|
| `finished_at` | the run's end, UTC |
| `outcome` | `ok` or `failed` |
| `snapshot` | the newest good snapshot's id, its first 8 characters |
| `database_bytes`, `files_bytes` | that snapshot's dump and files (the bytes restic processed less the dump) |
| `duration_seconds` | the run's |
| `first_run_at` | the first run's end, kept from run to run |
| `last_ok_at` | the newest good backup's time |
| `last_check_at`, `last_check_outcome`, `check_error` | the last monthly check: when, `ok` or `failed`, and its reason |
| `error` | a failed run's reason, else null |
| `cms_version` | the version that wrote it |

**A failure never hides how old the newest good backup is.** A run whose backup step succeeded and whose forget (or check run that a stop ended) then failed is `failed` with its reason, and records its own snapshot, sizes and `last_ok_at`; a run that failed at the dump or the backup, or for a missing secret, keeps the previous status's.

**Whole or absent.** The file is written to a temp file beside it and renamed (mode 0644), so the web never reads half of one. A file that is not this JSON, or names an outcome, a reason or a field type it does not know, reads as unreadable: System status says so, the alert stays quiet, and the next run starts as if there were none. No file reads as none.

**No secret.** No password, key, repository, destination or tool message: the fields above and nothing else. The folder is excluded from the backup itself, and `media:orphans`, which walks blob rows and never the disk, never sees it.

**The accessory's version file.** Beside it, `storage/backup/accessory.json` (`ContentSpiel::Backup::RunningVersion`), written by `schedule` when it starts, the same way (a temp file and a rename, mode 0644), and holding two fields and nothing else: `cms_version`, the version the accessory runs, and `started_at`, UTC. The status file's `cms_version` names the version that made the last run, so after `kamal accessory reboot backup` it would name the old version until the next day's run; this file names the new one from the moment the accessory starts. A file that is not this JSON (a version that is not a non-empty string, a time that is not ISO 8601) reads as none.

## System status and the alert

The Backups row (`Setup::SystemCheck#backups`, after Search), on System status only (the Dashboard draws no checks; the alert reaches the owners). Two states, as every check has:

- **ok** while the newest good backup is younger than 26 hours (`FRESH_BACKUP`: a day plus slack for a slow run) and nothing below applies: "Last backup 5 hours ago, 430 MB" (`backups.ok`, the age in `backups.age.*`: less than an hour, whole hours under 48, whole days beyond).
- **warning**, with the sentences that apply joined: no status file, "No backups are configured" with the link `BACKUPS_DOCS` to this file at the running version's tag (the web cannot tell a site without the accessory from one whose accessory never ran); an unreadable file, its own sentence; the last run failed, with its reason (`backups.reasons.*`); the newest good backup is 26 hours old or older, with its age, or there is none; the monthly check failed, with its reason; the accessory runs another CMS version than the site, with `kamal accessory reboot backup` to copy (`BACKUP_REBOOT_COMMAND`). The accessory's version is `accessory.json`'s, so the warning clears as soon as the rebooted accessory has started; without a readable `accessory.json` it is the status file's `cms_version`, the version of the last run. A failed run whose backup step succeeded carries a fresh good backup, so "failed" without "stale" is normal. The row names neither a snapshot nor the destination.

The words are `admin.system_status.backups.*` (`config/locales/admin/system_status.en.yml`). **The alert** `backup_stale` is raised at 48 hours without a good backup, 48 hours after the first run with none, or a failed monthly check, one per UTC day, mailed once, with no audit-log link; a single failed run alerts nothing: `docs/reference/alerting.md`, "Backups".

## The restore runbook

For a person, or an AI tool, bringing a site back on a new server (or the same one after its disk was lost), with the site's folder (its `config/deploy.yml`, `.contentspiel-version` and theme) and the destination's credentials at hand: `BACKUP_REPOSITORY`, `RESTIC_PASSWORD` and the bucket's key, from the password manager. Without `RESTIC_PASSWORD` no backup can be read. The target is two hours from the first step to the last check (the RTO); the drill measures it. Each step says what to run, from the site's folder, and what to see.

1. **A server with the site deployed, the web and the backup stopped.** Follow the site's README (step 4) on the new server: its `server_ip` in `config/deploy.yml`, the secrets in `.kamal/secrets` (the old site's `RESTIC_PASSWORD` and bucket key, the same `BACKUP_REPOSITORY`; **never `bin/backup init`**, the repository exists), and `kamal setup`, which boots the database accessory with empty databases (the first boot's `db:prepare` gives them the current schema, which step 3 drops), the backup accessory and the app. Then:

   ```sh
   kamal app stop
   kamal accessory stop backup
   ```

   You should see each container stopped. The backup is stopped so that no scheduled run fires on a half-restored site; its container stays, stopped, for step 7.
2. **Fetch the snapshot.** Open a shell in a new container of the backup accessory (it has the accessory's variables, the database's network and the files volume, read and write):

   ```sh
   kamal accessory exec backup --interactive "bash"
   ```

   Steps 2 to 4 are typed in that shell, one session: `/tmp/restore` lives only as long as the container, on the server's Docker disk, which needs room for the dump and the files twice over (the restored copy and the volume). First the snapshots, newest last:

   ```sh
   bin/backup list
   bin/backup restore latest /tmp/restore
   ```

   You should see the site's snapshots, each tagged `site=<name>` and `cms=<version>`, then `Restored snapshot latest into /tmp/restore: database.dump and files/. Nothing else was changed.` Take the id of the snapshot you mean instead of `latest` if a run was made on the new server already (it would be the newest, of an empty site). Its `cms=` tag must be no newer than the site's `.contentspiel-version`: a backup is restored with its own version or a later one.
3. **The database**, dropped, made again empty, and restored:

   ```sh
   PGPASSWORD="$POSTGRES_PASSWORD" dropdb --username postgres content_spiel_production
   PGPASSWORD="$POSTGRES_PASSWORD" createdb --username postgres --owner content_spiel --encoding UTF8 \
     --template template0 content_spiel_production
   PGPASSWORD="$POSTGRES_PASSWORD" pg_restore --no-owner --role=content_spiel \
     --username postgres --dbname content_spiel_production /tmp/restore/database.dump
   echo $?
   ```

   You should see no output and `0`. Each connects as `postgres` (the accessory's `PGHOST` is the database). The database is dropped first because step 1 loaded the current schema into it, and `pg_restore --clean` would drop only the objects the dump holds: the tables of migrations newer than the backup would survive, and step 5's `db:migrate` would then fail creating them again. `createdb` makes it as the database accessory's init script does (`config/postgres/10-contentspiel-databases.sh`: owned by `content_spiel`, `UTF8`, the image's `en_US.utf8` character type, which `docs/reference/hosting.md`, "Database requirements", asks for), from `template0`, the template with nothing added. `pg_restore` then creates everything owned by the site's role `content_spiel`, the audit log's append-only trigger and the `pg_trgm` extension included (both are in the dump). `dropdb: error: … is being accessed by other users` means a container still holds the database: step 1's two stops. A line `pg_restore: error:` is a finding: stop and read it before going on.
4. **The files.**

   ```sh
   cp -a /tmp/restore/files/. /rails/storage/
   ls /rails/storage
   exit
   ```

   You should see the volume's folders (Active Storage's two-letter folders, and `backup/` if the accessory ever wrote there). `exit` leaves the shell, and the container and `/tmp/restore` go with it.
5. **Migrations**, for a backup from an older CMS version (a new container of the app; nothing happens when the schema is current):

   ```sh
   kamal app exec "bin/rails db:migrate"
   ```

   You should see the migrations that ran, or nothing.
6. **The content version and the caches.** A restored database rewinds the public content version's counter, so the values that follow were used before, and a render or an ETag made under one of them would be served for the restored content:

   ```sh
   kamal app exec "bin/rails public_site:after_restore"
   ```

   You should see `Public content version: <a large number>` and `Cache cleared. If a CDN caches the site's pages, purge it now.` It jumps the counter to the wall clock in microseconds, or one past its value if that is greater (`PublicSite::Version.jump_past!`: every bump adds 1, so the counter is then above every value it held, as long as it never moved faster than a bump a microsecond), removes a stray version row, and empties `Rails.cache`, which holds the public render cache. Purge the CDN if one is in front. A site whose `SEARCH_BACKEND` is a gem's engine runs `kamal app exec "bin/rails search:reindex"` too; the built-in index is in the dump.
7. **Start, back up, check.**

   ```sh
   kamal app boot
   kamal accessory start backup
   kamal accessory exec backup --reuse "bin/backup run"
   ```

   You should see the app's container healthy, then `[backup] finished in ...s: snapshot ...`: the first backup of the restored site. Then check what the drill checks (below): a public page with an image, sign-in, a post's history, an image's original, a note's file, the audit log's newest entry from the backup's day, and System status, whose Backups row says *Last backup less than an hour ago*.

**Server snapshots** (a provider's image of the server's disk) are an extra layer, not a substitute: a quick way back from a broken upgrade on the same provider, but not encrypted under the site's key, not off the provider, and not the same for every site. A site may take them as well.

**Object lock.** A bucket's object lock or retention keeps an object from being deleted for a set time, even with the key, so a stolen key cannot erase the backups. But restic's daily `forget --prune` deletes data: the snapshots past the retention and the packs no snapshot uses. A lock that forbids deletes, or whose retention is shorter than what restic still keeps or prunes on another schedule, makes those deletes fail, and every run then fails at `forget` (its backup step still counts: `last_ok_at` moves, "The status file"), while the bucket keeps growing. Turn a lock on only with a retention that matches restic's, so an object is unlocked by the time restic may delete it (the longest restic keeps is six monthly snapshots, about six months, and a pack shared with a newer snapshot stays longer), or keep the bucket unlocked and protect it with the provider's own versioning and a policy that keeps deleted versions for a time. This is the one line the site's README defers here ("read the CMS's `docs/reference/backups.md` before you turn a lock on"). A lock is recommended on those terms only, and nothing requires one.

## The drill

A backup counts only once a restore has proved it. **Every quarter**, restore the newest backup into a scratch environment, a throwaway server deployed from a copy of the site's folder (another `server_ip`, another `PUBLIC_HOST`), **never the live database or the live server**, by following the runbook above, and time it from step 1 to the last check. On the scratch server the backup accessory stays stopped from step 1 to the end and is never started, and no `bin/backup run` is made there: its snapshots would join the live site's under the same host, and its `forget` would prune them as the site's. The drill's checks:

| Check | How |
|---|---|
| A page with an image renders | open it on the scratch site's address |
| A post's history opens | its History screen in CS Studio |
| An image's original downloads | "Download original" in the Media screen |
| A note's file opens | a note with a file, on any record |
| Sign-in works | an account of the backup's |
| The audit log's newest entry is from the backup's day | the audit log, newest first |

The evidence is a short dated record committed to the site's repository, `docs/restore-drills/YYYY-MM-DD.md`, a copy of the `docs/restore-drills/TEMPLATE.md` the site template writes: who, where, the CMS version of the backup and the one restored with, the snapshot, the duration against the two hours (a drill over two hours is a finding, with what took the time), each check's result, and the findings. Remove the scratch server afterwards; it holds a copy of every page and every account.

## In tests

**The unit suite** drives a fake runner (`test/support/fake_backup_runner.rb`, `FakeBackupRunner`): neither restic nor `pg_dump` 17 is on a laptop or a CI runner, and nothing is installed at test time. It records every call's argv and environment and answers each step from a script, so `test/lib/content_spiel/backup_test.rb` holds the steps, their arguments, the status on success and at each failure, the monthly check, the schedule with a fake clock and sleeper, the signals (`bin/backup` itself, in a child process, for TERM and INT while it sleeps) and that no secret reaches stdout, stderr or the status file; `Runner` is held against real child processes (`ruby -e`). `test/lib/content_spiel/backup/failure_test.rb`, `status_test.rb` and `running_version_test.rb` hold the reasons and the two files; `test/models/setup/system_check_test.rb` the row ("Backups: …"); `test/queries/alerts/backup_rule_test.rb` the alert; `test/tasks/public_site_tasks_test.rb` and `test/models/public_site/version_test.rb` the restore's version jump; `test/lib/site_generator_test.rb` and `test/lib/upgrade_test.rb` the template and `upgrade`; `test/lib/backup_image_test.rb` the `Dockerfile`'s packages.

**The real tools** run in `image.yml`'s job `site-template` (`docs/reference/hosting.md`, "What the site template's CI job holds"): "The image's backup tools" reads the image's restic (at least 0.16) and `pg_dump` (no older than the template's Postgres), and "Back up and restore the booted site" runs the image's `bin/backup init`, `run`, `list` and `restore` against the booted site's database with a `local:` repository, and checks the status file, the snapshot, the restored probe file and dump, and that the made-up `RESTIC_PASSWORD` is in nothing a command said. The job runs on every merge to `main`, not for a pull request: a change to `bin/backup` or the `Dockerfile`'s tools is tried on its branch by hand, `gh workflow run Image --ref <branch>` and then `gh run watch`, before it is merged.

## What a change can break silently

- **A random path or host in a snapshot** (a dump folder from `Dir.mktmpdir`, a `--host` left out so restic takes the container's random hostname) makes each snapshot a group of its own: `forget` keeps every one and the bucket grows forever, with every run green.
- **A change of `DUMP_DIR`, `DATABASE` or the app root** changes the paths in every new snapshot, and `restore` looks for the dump by those paths: a snapshot taken before the change no longer restores with the new command (use the old version's image for it).
- **A new step or tool whose stderr is printed, logged, raised in an exception's message or written into the status file** can put a password, a key or the bucket's address in the accessory's log.
- **A new write into the files volume outside `storage/backup/`** (a dump, a cache, a lock file) changes the site's own files and is backed up with them.
- **The template's Postgres moved to a newer major** without the image's `postgresql-client-NN`: `pg_dump` refuses a server newer than itself, and every run fails as `other`.
- **A change of the alert that updates the day's row** instead of inserting it once moves `last_seen_at` every minute, and `Alert.due` mails it again every hour.
- **A `bin/backup run` beside the schedule in a new container** (`kamal accessory exec backup "bin/backup run"`, without `--reuse`) has its own `/tmp`, so the run lock does not see the scheduled run: the two then dump and write the status at once. The runbook, the README and `upgrade` carry `--reuse`.
- **System status reading the accessory's version from the status file alone** (or a `schedule` that stops writing `accessory.json`) brings back a warning that names the old version from a reboot to the next day's run.
- **A Kamal command that changes meaning between Kamal versions** (`accessory exec` without `--reuse` starting a new container, `accessory reboot` taking the image anew, `app exec` running in a new container): the runbook, the README and `upgrade`'s output were checked against Kamal 2.12's `kamal help accessory` and `kamal help app`.
- **A provider's S3 error words that `Failure` does not know** read as `other`, so System status says "an unexpected error" where the destination could not be reached.

## Rules a change can break silently

- Every snapshot is taken with `--host <BACKUP_SITE>` and the same two paths, and `forget` narrows to that host (`test/lib/content_spiel/backup_test.rb`: "every snapshot is taken with the site as its host and the same two paths, and forget narrows to that host", "the site's name defaults to contentspiel"); the retention, the check's parts, the dump's place and the database are fixed (same file: "the constants are the command's fixed values"). **No guard** that a snapshot taken under an older `DUMP_DIR` still restores.
- No tool's message reaches stdout, stderr or the status file during a run, and `list` and `init` print restic's stdout with every secret and the repository hidden (`test/lib/content_spiel/backup_test.rb`: "a tool's message holding every secret reaches neither the output nor the status file", "list and init hide the repository with or without its trailing slash"; `test/lib/content_spiel/backup/status_test.rb`: "the status file names no secret field"; `test/models/setup/system_check_test.rb`: "Backups: no message names the snapshot or the repository"); with the real tools, `image.yml`'s "Back up and restore the booted site" fails when any command printed the password.
- A missing secret is named by its name, recorded as its reason, and starts no tool; a tool gets a closed stdin, `--no-password`, no shell and only its own variables under a fixed `PATH` (`test/lib/content_spiel/backup_test.rb`: "a missing secret is named, recorded as its reason, and no tool is started", "children get only the variables they need", "the runner hands the child only the given environment and a closed stdin, never through a shell", "values that are not secret are read stripped, secrets as given").
- The status file is whole or absent, and an unreadable one is a warning row, never an error page or an alert (`test/lib/content_spiel/backup/status_test.rb`: "a write is whole or absent: a temp file and a rename", "no file reads as nil, and a file that is not the status reads as unreadable"; `test/models/setup/system_check_test.rb`: "Backups: an unreadable status file is a warning that says so"; `test/queries/alerts/backup_rule_test.rb`: "no status file, or an unreadable one, raises nothing"; `test/lib/content_spiel/backup_test.rb`: "an unreadable previous status counts as none").
- A failed run keeps the newest good backup's time: its own snapshot when the backup step succeeded, the previous one's otherwise (`test/lib/content_spiel/backup_test.rb`: "a failure at each step writes a failed status with its reason, and exits 1"), and a failed check leaves the backup ok and is retried at the next run ("a failed check keeps the backup ok and records its reason", "the monthly check runs on the first run of a month, and again after a failed check").
- The command writes nothing in the files volume but `storage/backup/`, and `media:orphans` never touches it (`test/lib/content_spiel/backup_test.rb`: "run writes nothing in the files volume but its own folder", "unconfigured, schedule says so once a day and runs nothing"; `test/tasks/media_orphans_backup_test.rb`: "media:orphans never touches the backup folder").
- One run at a time: a run that finds the lock held starts no tool and writes no status, and a run releases the lock however it ends (`test/lib/content_spiel/backup_test.rb`: "a run while another holds the run lock says so, exits 1, starts no tool and writes no status", "the run lock is released after a run, a failed one too"). **No guard** for two runs in two containers: the lock is on each container's own disk.
- `schedule` writes the accessory's version when it starts, with no secret, and System status compares it, falling back to the status file's version when it cannot be read (`test/lib/content_spiel/backup_test.rb`: "schedule writes the accessory's version when it starts, before it sleeps, and nothing secret", "a schedule that cannot write the accessory's version says so by its class and goes on"; `test/lib/content_spiel/backup/running_version_test.rb`: "no file, or one that is not this JSON, reads as nil"; `test/models/setup/system_check_test.rb`: "Backups: the accessory's own version wins over the status's, so a reboot clears the warning before the next run", "Backups: without the accessory's file (none, or unreadable) the status's version is compared"). **No guard** that a status write which fails ends `schedule` and that Kamal's restart policy brings it back: Kamal 2.12's default, read by hand.
- One run a day, never a retry, and a stop ends cleanly (`test/lib/content_spiel/backup_test.rb`: "schedule sleeps until the hour, runs once a day, and does not retry a failure", "a wall clock set back after a run does not give a second run that day", "stop! while sleeping ends the schedule with 0; during a run it interrupts the tool and records the run as failed", "bin/backup ends its schedule at TERM or INT while it sleeps, with 0").
- The command loads with plain Ruby (`test/lib/content_spiel/backup_test.rb`: "the command loads with plain Ruby, without Rails").
- The image's `pg_dump` is no older than the template's Postgres (`test/lib/backup_image_test.rb`: "the image installs restic and a pg_dump no older than the template's Postgres"; `image.yml`'s "The image's backup tools" for what Debian actually installed).
- The web container gets no backup variable, and the accessory's block uncommented is valid Kamal configuration with the web's files volume and database host (`test/lib/site_generator_test.rb`: "the web container gets no backup variable", "deploy.yml carries the backup accessory commented, and uncommented it is valid Kamal configuration"); the README's commands are `bin/backup`'s subcommands and the drill record holds the six checks ("the README's backup commands are bin/backup's subcommands", "the drill record names the snapshot, the duration against the two hours, and each check"). **No guard** reads the Kamal commands of this runbook, the README or `upgrade` against the installed Kamal: they were checked by hand against Kamal 2.12.
- `upgrade` reads `deploy.yml` and never writes it, and offers the block only to a site with no `backup:` line (`test/lib/upgrade_test.rb`: "upgrade never writes deploy.yml", "a commented block is not printed again", "with the accessory configured, the backup before deploying is bin/backup run, and the last step reboots the accessory").
- After a restore the content version is above every value it held and the cache is empty (`test/tasks/public_site_tasks_test.rb`: "after_restore puts the version above every value the counter held, and empties the cache"; `test/models/public_site/version_test.rb`: "jump_past! moves a small counter to the floor and a larger one by one", "jump_past! deletes a stray row of another id"). **No guard** that a person runs it: it is a step of the runbook.
- A backup alert is one row a UTC day, mailed once (`docs/reference/alerting.md`, "Rules a change can break silently").
- **No guard** for a provider's S3 error words that `Failure::RESTIC_DESTINATION` does not know: they read as `other`. **No guard** for the runbook's `dropdb`, `createdb` and `pg_restore` against a real database: CI's step lists the dump (`pg_restore --list`), it does not restore it; the drill does.
