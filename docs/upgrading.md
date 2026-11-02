# Upgrading

There are two kinds of update:

- **Runtime updates** contain PHP, operating system and media tool fixes. They
  are published under the existing version tag (e.g. `2.0.11`) and don't
  change the database.
- **Application updates** move to a new Providence version. They get a new tag
  and may change the database.

## Runtime updates

```sh
docker compose pull web && docker compose up -d
```

To roll back, set `CA_IMAGE_TAG` to an earlier build (e.g. `2.0.11-r41`) and
run `docker compose up -d`.

## Application updates

### 1. Prepare the image

Renovate opens a pull request for each new Providence release. Before merging
it:

1. Read the release notes for database changes, search index rebuilds and
   changed requirements.
2. Update `CA_SHA256` in `docker/Dockerfile`. The build fails until you do.

   ```sh
   VERSION=2.0.12
   curl -fsSLO "https://github.com/collectiveaccess/providence/releases/download/${VERSION}/providence-${VERSION}.zip"
   sha256sum "providence-${VERSION}.zip"
   ```

3. Check which PHP version the bundled dependencies need. If it has changed,
   update both `FROM` lines in `docker/Dockerfile`.

   ```sh
   unzip -p "providence-${VERSION}.zip" vendor/composer/platform_check.php | grep PHP_VERSION_ID
   ```

4. Compare the release's `setup.php-dist` with `docker/setup.php` (and your own
   `setup.php`, if you use one) and add any new options.

### 2. Test

Run the `pr-<number>` image as a second stack on a different port, with
`CA_APPDATA` pointing at a copy of your data, then:

```sh
docker compose exec web cautils update-database-schema
```

Open some records, upload an image and a video, and run a search.

### 3. Deploy

Merging publishes the new version tag. The previous tag stops receiving weekly
rebuilds.

1. Run `scripts/db-backup.sh`, and snapshot `CA_APPDATA` if your storage
   supports it.
2. Set `CA_IMAGE_TAG` to the new version and run `docker compose up -d`.
3. Update the database:

   ```sh
   docker compose exec web cautils update-database-schema
   ```

4. Do anything else the release notes ask for, such as
   `cautils rebuild-search-indices`.

To roll back, restore the database from the backup and set `CA_IMAGE_TAG` back
to the previous version.

For major version changes, also read the
[Providence upgrade notes](https://docs.collectiveaccess.org/providence/category/upgrades).

## MySQL and Redis

Renovate opens pull requests for these but never merges them. Redis holds only
cache data and can be upgraded at any time. Before upgrading MySQL, check which
versions Providence supports and back up the database.
