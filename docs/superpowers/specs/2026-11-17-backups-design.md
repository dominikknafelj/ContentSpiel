# Backups, a restore runbook and a restore drill

Issue #175 (priority high; SOC 2 CC7.5, A1.2, A1.3). Decided with the owner on 2026-11-17.

## Intent

Every ContentSpiel site can lose its server, its disk or its database and come back with its content, accounts and images. Today nothing backs up or restores: Postgres runs as a Kamal accessory on the site's own server, the library's images and notes' files sit in the named volume mounted at `/rails/storage`, and the only backup is a command a person types by hand (`pg_dumpall`, in the site template's README and in `contentspiel upgrade`'s next steps). One failed disk loses the site.

The guide (contentspiel-docs) is the first site to run it, but the feature is the CMS's and the site template's, for every site (`feedback: CMS changes are generic`).

## Goals

- Encrypted backups, off the server, on a schedule, of everything a site needs to come back: the primary database and the files volume.
- One kind of destination: an **S3-compatible bucket**. The owner named Hetzner Object Storage, Cloudflare R2 and Amazon S3; all three, and others speaking the protocol (Backblaze B2, MinIO), are one configuration with an endpoint.
- A restore runbook a person (or an AI tool) can follow step by step on a new server, including what a restore needs beyond the data: the content version jumped past its old values and the caches emptied.
- A restore drill: a written procedure, repeated every quarter, whose evidence is written down.
- Written recovery targets.
- System status shows the age and outcome of the newest backup, and warns when it is too old.

## Non-goals

- The media library in a bucket (Active Storage on S3). It is its own feature, later; this design only adds its roadmap row (see "Roadmap").
- Point-in-time recovery (WAL archiving). A daily dump is the target; PITR is a later step if a site needs a smaller loss window.
- Backing up the cache, queue and cable databases (`content_spiel_production_cache`, `_queue`, `_cable`): they are rebuilt empty. A queued job lost with them is acceptable (the recurring jobs come back from `config/recurring.yml`).
- Backups from or in CS Studio (a "Back up now" button, choosing a destination in Settings). The destination's credentials stay with the host, as every other secret does.
- SFTP or a storage box as a destination (the owner chose S3-compatible buckets).
- Backups of a site that is not deployed with the site template's Kamal setup. Its README section says what to back up and how, and the image's command works anywhere the image runs with the volume and the database reachable.

## Anti-goals

- A backup the site cannot restore. A backup counts only once the drill has restored it.
- A secret in a log, a status file, a page or the bucket's object names: the restic password, the bucket's keys and the database password are never printed, written to the status file or shown on System status.
- A stuck or broken website stopping backups, or a running backup slowing the website noticeably.
- A restore that serves stale pages: a restored database whose content version repeats numbers already used (`docs/roadmap.md`, "A restored backup rewinds the version counter…").

## Recovery targets

- **RPO: 24 hours.** One backup a day; at most a day of changes is lost. (Proposed, not objected to by the owner.)
- **RTO: 2 hours** for a person following the runbook on a new server, with the destination's credentials at hand. The drill measures it; a drill above it is a finding.
- **Retention:** 7 daily, 4 weekly, 6 monthly snapshots (`restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune`).
- **Integrity:** `restic check` once a month, reading a subset of the data (`--read-data-subset=1/12`, so a year reads everything once).

## Approaches considered

1. **A backup accessory running the site's own image (chosen).** Kamal starts a second container of the site's image with a backup command instead of the web server, on the same server, with the files volume mounted read-only and the database reachable by its accessory name. It dumps the primary database, then runs restic, which encrypts, deduplicates and sends to the bucket, and keeps the retention. It is separate from the web process (a stuck site does not stop it), versioned with the CMS (the image carries the right `pg_dump` and restic, so nothing to install on the server), and the same for every site from the template.
2. **The CMS backs itself up from a Solid Queue job.** Easiest to show in CS Studio, but large files and a dump run inside the web application's job worker, the worker's health decides the backups', and a restore would still need a tool outside the application. Rejected.
3. **Leave it to the host** (server snapshots, a managed database's backups) and write only the runbook. Cheapest, but not encrypted under the site's key, not off the provider and not the same for every site. Rejected; the runbook mentions snapshots as an extra layer.

## Design

### The command

A new command in the image, `bin/backup` (plain Ruby or shell; the builder's call), with subcommands:

- `bin/backup run`: one backup now.
  1. `pg_dump --format=custom` of the primary database (`content_spiel_production`) as the superuser `postgres`, into a temporary directory on the container's own disk (not the files volume). The custom format restores with `pg_restore`, per table, and is compressed.
  2. `restic backup` of the dump and of `/rails/storage` (read-only mount), tagged with the site's name and the CMS version, one snapshot.
  3. `restic forget` with the retention above, `--prune`.
  4. Once a month (the first run on or after the 1st), `restic check --read-data-subset=n/12`, n the month.
  5. Writes the status file (below), whether it succeeded or failed, and exits non-zero on failure.
- `bin/backup schedule`: the accessory's long-running command. Runs `run` once a day at a set hour (`BACKUP_HOUR`, UTC, default 3), sleeping between runs; no cron daemon. A run that fails is not retried until the next day, so a broken destination produces one failure a day, not a loop.
- `bin/backup list`: the snapshots (restic's own list).
- `bin/backup restore <snapshot|latest> <target dir>`: fetches a snapshot's dump and files into a directory, for the runbook. It does not touch a database or the live volume itself.
- `bin/backup init`: creates the restic repository in the bucket (once per site).

The image installs `restic` from Debian's packages beside `postgresql-client` (already installed). **`pg_dump` must be at least the server's major version** (Postgres 17 in the template): the builder checks the image's client version and pins `postgresql-client-17` from the PGDG repository if Debian's is older, with a test that fails when the image's `pg_dump --version` is below the template's `postgres_version`.

### Which image the accessory runs (decided by Claude, 2026-11-17)

A Kamal accessory has one fixed `image:` and `kamal deploy` does not reboot it. The accessory therefore runs the **CMS image at the site's pinned version** (`<cms_image>:<version>`, the version read by ERB from `.contentspiel-version` in `deploy.yml`), not the site's own image: backups need no theme, and the version is the one the site runs. After a deploy that changes the version, `kamal accessory reboot backup` moves it along; `contentspiel upgrade`'s next steps say so as their last step. The backup *before* an upgrade's deploy runs on the old version, which is right: it dumps the old schema. Drift between the two is harmless for a dump (pg_dump reads any schema), and the status file carries `cms_version` so System status can say "the backup runs 0.10.1, the site 0.11.0" as part of its warning when they differ.

### Configuration

Environment variables on the backup accessory only (the web container gets none of them):

| Variable | What |
|---|---|
| `BACKUP_REPOSITORY` | restic's repository, `s3:<endpoint>/<bucket>/<prefix>`, e.g. `s3:https://<account>.r2.cloudflarestorage.com/backups/my-site` or `s3:https://fsn1.your-objectstorage.com/backups/my-site` |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | the bucket's key pair (restic's own names). Secret |
| `RESTIC_PASSWORD` | the repository's encryption password. Secret; **losing it loses every backup** |
| `AWS_DEFAULT_REGION` | where the provider asks for one (`auto` for R2) |
| `BACKUP_HOUR` | optional, 0–23 UTC, default 3 |
| `PGHOST`, `POSTGRES_PASSWORD` | the database accessory and its superuser, as the site template already has |

Unset `BACKUP_REPOSITORY`: the command says backups are not configured and exits 0; `schedule` sleeps and says so once a day. A site without backups configured is a warning on System status, not an error at boot.

The bucket's key should be allowed to write and read but not delete objects older than the retention if the provider supports it (object lock / bucket-level retention); the runbook recommends it, the design does not require it.

### The status file

`/rails/storage/backup/status.json`, written by the accessory, read by the web container. The backup accessory therefore mounts the files volume read-write for that one directory; the builder decides how (a second mount of a subdirectory, or the whole volume read-write with the command never writing elsewhere, held by a test). It holds:

```json
{ "finished_at": "2026-11-18T03:04:12Z", "outcome": "ok",
  "snapshot": "1a2b3c4d", "database_bytes": 18234567, "files_bytes": 412345678,
  "duration_seconds": 84, "last_check_at": "2026-11-01T03:06:00Z", "last_check_outcome": "ok",
  "error": null, "cms_version": "0.11.0" }
```

`error` holds a short reason without secrets or full command lines (restic's and pg_dump's messages are summarised to a fixed set: destination unreachable, wrong password, database unreachable, disk full, other). The last successful run's time is kept beside the last attempt's (`last_ok_at`), so a failure does not hide how old the newest good backup is. The directory is excluded from the backup itself, and from `media:orphans`.

### System status

A "Backups" row (`Setup::SystemCheck`), on System status as the other checks are (the Dashboard lists no checks; the alert reaches owners):

Two states only, the ones every check has (decided by Claude, 2026-11-17; no new `:error` state, so no new look; the wording goes to the Design System for its card):

- **ok:** the newest good backup is younger than 26 hours: "Last backup 5 hours ago, 430 MB" (no snapshot id, no destination).
- **warning:** no status file (backups not configured): "No backups are configured" with a link to the guide page; or the newest good backup is older than 26 hours (its age); or the last run failed (its reason); or the monthly check failed; or the accessory's CMS version differs from the site's.

**The alert** (`docs/reference/alerting.md`): a new kind, `backup_stale`, raised by the existing alerts check job when the newest good backup is older than 48 hours or the monthly check failed, fingerprinted by day (one alert a day while it lasts), shown on System status's Alerts card and mailed by the digest like the others, with no audit-log link. A single failed run alerts nothing by itself: the next day's run usually succeeds, and two missed days reach the 48 hours (decided by Claude, 2026-11-17).

### The site template

- `config/deploy.yml.tt`: a `backup` accessory, commented out with its placeholders filled by the README's step, using the CMS image at the site's pinned version (`image: <cms_image>:<version from .contentspiel-version>`, `cmd: bin/backup schedule`; see "Which image the accessory runs"), the files volume, the database's network name and the env above.
- `.kamal/secrets.example`: the three secrets with how to make each (`openssl rand -base64 32` for the restic password, "keep it in your password manager; losing it loses every backup").
- README: a "Backups" step after the first deploy: create the bucket and its key at one of the three providers (one short paragraph each, links), fill the variables, `kamal accessory boot backup`, `kamal accessory exec backup "bin/backup init"`, `... "bin/backup run"`, and what System status should then say.
- **Existing sites** (decided by Claude): `contentspiel upgrade` to the release that ships this prints the accessory's block and the three secrets to paste when `deploy.yml` has no `backup` accessory, and the CHANGELOG names it; it never edits `deploy.yml` itself.
- `contentspiel upgrade`'s next steps: "make a backup before step 3" becomes `kamal accessory exec backup "bin/backup run"` when the accessory is configured, keeping the `pg_dumpall` command as the fallback.

### The restore runbook

`docs/reference/backups.md` (the reference) and a guide page for administrators (contentspiel-docs, written at release). Steps, each with what to run and what to see:

1. A server with the site deployed from its folder (the template's steps), web stopped (`kamal app stop`), the database accessory running with empty databases.
2. `bin/backup restore latest /restore` in a one-off container of the backup accessory with `/restore` on the host.
3. `pg_restore --clean --if-exists --no-owner --role=content_spiel -d content_spiel_production` from the dump; the audit log's append-only trigger is in the dump.
4. The files copied into the files volume.
5. `bin/rails db:migrate` (a backup from an older CMS version).
6. **The content version jumped past every value used before** and the caches cleared: a new task, `bin/rails public_site:after_restore`, which sets the version counter to a value no earlier backup can have reached (the builder chooses how: e.g. the current time in microseconds, or the old maximum plus a margin read from the dump's metadata), clears the Rails cache (Solid Cache) and the public render cache, and says to purge the CDN if one is in front. This closes the roadmap's known trap (`docs/roadmap.md`, "A restored backup rewinds the version counter…").
7. `kamal app boot`; check System status, a public page, sign-in.

### The restore drill

`docs/reference/backups.md`, "The drill": every quarter, restore the newest backup into a scratch environment (a throwaway server or a local `contentspiel dev`-style stack, never the live database), run the runbook, time it, and check a fixed list (a page with an image renders, a post's history opens, an image's original downloads, a note's file opens, sign-in works, the audit log's newest entry matches the backup's day). The evidence is a short dated record committed to the site's repository (`docs/restore-drills/YYYY-MM-DD.md`, a template provided by the site template) naming the snapshot, the duration against the RTO and each check's result. The first drill is run on the guide once the CMS release is deployed there; it is not part of the CMS pull request.

### The guide (contentspiel-docs), a separate pull request

The CMS work ships the command, the template and the docs. The guide's own setup is a pull request in contentspiel-docs after the release: the `backup` accessory in its `config/deploy.yml` (its own file, not the template's), the three secret names in its secrets example, the bucket in `tofu/` if the provider is managed there, and the first drill's record. **The owner creates the bucket, its key and the restic password** and puts them in 1Password; Claude never handles them. The guide's provider: **Cloudflare R2** (the owner, 2026-11-17): a provider other than the server's (Hetzner), no fee for reading a restore back, and the domain is already at Cloudflare.

### Telemetry

The accessory sends no spans (it has no OTEL setup by design: one fewer moving part). Its log lines on stdout (`kamal accessory logs backup`) say each step's start, end and size, never a secret.

## Roadmap

Add under Media a row: **Library files in an S3-compatible bucket** (Should): Active Storage's S3 service as an option set by variables (bucket, endpoint, region, keys), the disk staying the default; served through Rails as now so the originals stay editors' and only made widths are fetched; a command that moves existing files into the bucket and checks each; a System status row; `aws-sdk-s3` required only when configured. It makes hosts without a lasting disk and more than one app server possible; with it, a site's backup covers the database while the bucket's own versioning covers the files. Decided 2026-11-17: after this design.

## Tests

- The command, against a local S3-compatible server is not available in CI without a download: the builder uses restic's `local:` repository in tests (same code path but the backend) and a test database, covering run, retention, the status file on success and on each failure class, and that no secret reaches stdout, stderr or the status file.
- The status file's reader and the System status row's two states and their words (`Setup::SystemCheck` tests).
- `public_site:after_restore`: the version after it is above any value the counter held, and the caches are empty.
- The image: `restic version` and `pg_dump --version` (major ≥ the template's Postgres) in the image test.
- The site template: the generated `deploy.yml` with the accessory uncommented passes `kamal config` validation shape tests the template already has, and the README's commands match the command's subcommands.

## Left to the builder

- Ruby or shell for `bin/backup`; how the status directory is mounted writable; how the schedule sleeps; the version jump's exact rule; where the image's restic comes from if Debian's is too old for R2 (restic ≥ 0.16).

## Documentation

Guide: a new administrators' page "Backups and restore" (set up with each of the three providers, the runbook, the drill), and changes to "Install" (the backup step) and "Upgrading" (the backup command). Integrators: none.
