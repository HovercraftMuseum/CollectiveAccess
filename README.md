# CollectiveAccess Providence for Docker

A container image and Docker Compose stack for
[CollectiveAccess Providence](https://collectiveaccess.org).

The image contains the official Providence release, PHP, Apache and the media
tools Providence uses (FFmpeg, Ghostscript, GraphicsMagick, ImageMagick,
Poppler, MediaInfo, ExifTool). The Compose stack adds MySQL and Redis. All data
and configuration are kept in folders on the host.

## Quick start

1. Copy `compose.yaml`, `.env.example` and `scripts/` into a folder on the host.
2. Copy `.env.example` to `.env`, fill it in, and `chmod 600 .env`.
3. Create the storage folders set in `.env` (see [Storage](#storage)).
4. Run `docker compose up -d`.
5. [Install CollectiveAccess](#installing-collectiveaccess).

## Configuration

### Environment variables

`.env.example` lists every variable. You must set:

| Variable | Purpose |
|---|---|
| `CA_IMAGE`, `CA_IMAGE_TAG` | Image to run, e.g. `ghcr.io/OWNER/collective-access` and `2.0.11` |
| `CA_DB_PASSWORD` | Password for the CollectiveAccess database user |
| `CA_DB_ROOT_PASSWORD` | MySQL root password (used for backups) |
| `CA_ADMIN_EMAIL` | Address that receives system error reports |
| `CA_APPDATA`, `CA_MEDIA`, `CA_BACKUPS`, `CA_INGEST` | Host folders; see [Storage](#storage) |

Others you may want to change:

| Variable | Default | Purpose |
|---|---|---|
| `CA_APP_DISPLAY_NAME` | `CollectiveAccess` | Name shown on the login page and in emails |
| `CA_TIMEZONE` | `UTC` | PHP time zone name |
| `CA_DEFAULT_LOCALE` | `en_US` | Must exist in your installation profile |
| `CA_UID`, `CA_GID` | empty | Owner of the storage folders (see [Ownership](#ownership)) |
| `CA_HTTP_BIND`, `CA_HTTP_PORT` | `0.0.0.0`, `8080` | Where the web interface listens. Don't expose it to the internet. |
| `CA_DB_BUFFER_POOL` | `1G` | MySQL InnoDB buffer pool size |
| `CA_SMTP_*` | empty | Outgoing mail server |
| `CA_STACKTRACE_ON_EXCEPTION` | `false` | Show full errors in the browser |
| `CA_LOG_KEEP_DAYS` | `30` | Days of Providence log files to keep (see [Scheduled jobs](#scheduled-jobs)) |

### setup.php

The image's `setup.php` takes its values from the environment variables above.
To use your own instead, start from `setup.php-dist` in the
[Providence release](https://github.com/collectiveaccess/providence/releases),
save it as `${CA_APPDATA}/config/setup.php`, and uncomment the matching line in
`compose.yaml`.

### Configuration overrides

To change a setting in one of Providence's configuration files (`app.conf`,
`search.conf` and so on), create a file with the same name in
`${CA_APPDATA}/config/local/` containing only the settings you want to change,
then restart the `web` container. For example:

```
# ${CA_APPDATA}/config/local/app.conf
batch_media_import_root_directory = /srv/ingest
```

## Storage

| Variable | Contents | Back up? |
|---|---|---|
| `CA_APPDATA` | `config/`, the database (`db/`) and usually the stack folder | Yes |
| `CA_MEDIA` | Uploaded media and generated derivatives | Yes |
| `CA_BACKUPS` | Database dumps and a copy of the configuration | Yes, off-site |
| `CA_INGEST` | Files waiting to be imported | Optional |

An example layout, with fast storage under `/srv/fast` and large storage under
`/srv/bulk`:

```
/srv/fast/appdata/collectiveaccess        CA_APPDATA
├── stack/            compose.yaml, .env, scripts/
├── config/
│   ├── local/        configuration overrides
│   └── setup.php     optional
└── db/               MySQL data

/srv/bulk/appdata/collectiveaccess/media  CA_MEDIA
/srv/bulk/backups/collectiveaccess        CA_BACKUPS
├── database/         SQL dumps
└── application/      copy of stack/ and config/
/srv/bulk/ingest                          CA_INGEST
```

### Container paths

| Host | Container | Mode |
|---|---|---|
| `${CA_APPDATA}/config/local` | web: `/var/www/html/app/conf/local` | read-only |
| `${CA_APPDATA}/config/setup.php` (optional) | web: `/var/www/html/setup.php` | read-only |
| `${CA_MEDIA}` | web: `/var/www/html/media/collectiveaccess` | read-write |
| `${CA_INGEST}` | web: `/srv/ingest` | read-only |
| `${CA_APPDATA}/db` | db: `/var/lib/mysql` | read-write |
| `${CA_BACKUPS}/database` | db: `/backups` | read-write |

Two Docker volumes hold files that don't need backing up:

- `ca-tmp`: temporary files (uploads in progress, media processing, exports).
  During large media jobs it can briefly need several times the size of the
  file being processed, so leave room on Docker's disk.
- `ca-log`: Providence's logs. Read them with
  `docker compose exec web ls /var/lib/collectiveaccess/log`. PHP and web
  server errors go to `docker compose logs web`.

### Ownership

Set `CA_UID` and `CA_GID` to the numeric user and group that own the storage
folders, and the web server runs as that user. If they are empty, the folders
must be writable by UID 33.

## Installing CollectiveAccess

Run the installer in the browser at `http://<host>:8080/install/`, or:

```sh
docker compose exec web cautils install --profile-name=default --admin-email=you@example.org
```

Note the administrator password it prints.

Providence ships with several installation profiles, and more are in the
[InstallationProfiles](https://github.com/collectiveaccess/InstallationProfiles)
repository. To use your own, mount it into `/var/www/html/install/profiles/xml/`.

## Command-line tools

`cautils` runs Providence's `caUtils` as the web server user:

```sh
docker compose exec web cautils help
docker compose exec web cautils rebuild-search-indices
docker compose exec web cautils update-database-schema
```

## Scheduled jobs

Run these daily from the stack folder, e.g. from cron:

```sh
scripts/db-backup.sh                          # see Backups
docker compose exec -T web ca-prune-logs      # delete old Providence log files
```

Container logs (`docker compose logs`) are rotated by Docker at 50 MB per
service.

## Backups

`scripts/db-backup.sh` dumps the database and copies the stack and config
folders to `CA_BACKUPS`. Set `KEEP_DAYS` to delete dumps older than that many days. Back up
`CA_MEDIA` separately.

To restore a dump:

```sh
docker compose exec -T db sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot "$MYSQL_DATABASE"' \
  < collectiveaccess_YYYY-MM-DD_HHMMSS.sql
```

## Image tags and updates

| Tag | Meaning |
|---|---|
| `2.0.11` | Latest build of Providence 2.0.11 |
| `2.0.11-r42` | One specific build; never changes |
| `sha-<commit>` | Build from a specific commit of this repository |
| `pr-<number>` | Build from a pull request, for testing |

The image is rebuilt weekly and when its base image changes, so security
fixes arrive under the same version tag:

```sh
docker compose pull web && docker compose up -d
```

To move to a new Providence version, follow [docs/upgrading.md](docs/upgrading.md).

## Building your own image

Fork this repository and enable GitHub Actions. The workflow builds and tests
the image, then publishes it to `ghcr.io/<owner>/<repository>`. Make the
`build` check required on your default branch, since
[Renovate](https://docs.renovatebot.com/) merges some updates automatically.

To include LibreOffice for Office document previews, build with
`--build-arg INSTALL_LIBREOFFICE=true`.

## Licence

[GPL-3.0](LICENSE)
