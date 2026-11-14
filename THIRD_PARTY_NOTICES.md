# Third-party notices

WalletWeather's own code is under the [MIT licence](LICENSE). The container
image published for each release also contains software written by other
people, under their own licences. None of it is modified. This page lists
it; each package's full licence text ships inside the image, in the
package's `.dist-info` folder under
`/install/lib/python3.12/site-packages/`, and for the operating system under
`/usr/share/doc/*/copyright`.

The web client (`apps/web`) contains no third-party code, fonts or images.

Checked on 2026-11-14 against WalletWeather 1.22.2 by installing
`apps/server/requirements.txt` in a clean `python:3.12-slim` container.
Packages marked "direct" are pinned in that file; the others are pulled in
by them and their versions can move between builds.

## Copyleft packages

Two packages are under licences that ask for more than a notice. Both are
used as published, unmodified.

- **psycopg and psycopg-binary 3.2.3** (direct): GNU Lesser General Public
  License v3. Source: <https://github.com/psycopg/psycopg>. The LGPL lets
  you replace this library with your own build of it, which a Python
  package allows as it stands: install another version over it. The binary
  package bundles **libpq** (PostgreSQL License) and **OpenSSL**
  (Apache-2.0).
- **certifi**: Mozilla Public License 2.0. Source:
  <https://github.com/certifi/python-certifi>. It is Mozilla's list of
  trusted certificate authorities, pulled in by `httpx`.

## Python packages

| Package | Licence | |
| --- | --- | --- |
| annotated-types | MIT | |
| anyio | MIT | |
| APScheduler 3.10.4 | MIT | direct |
| Authlib 1.3.2 | BSD-3-Clause | direct |
| bcrypt 4.2.0 | Apache-2.0 | direct |
| certifi | MPL-2.0 | see above |
| cffi | MIT-0 | |
| click | BSD-3-Clause | |
| cryptography 43.0.1 | Apache-2.0 or BSD-3-Clause | direct |
| fastapi 0.115.0 | MIT | direct |
| greenlet | MIT and PSF-2.0 | |
| h11 | MIT | |
| httpcore | BSD-3-Clause | |
| httptools | MIT | |
| httpx 0.27.2 | BSD-3-Clause | direct |
| idna | BSD-3-Clause | |
| itsdangerous 2.2.0 | BSD-3-Clause | direct |
| psycopg, psycopg-binary 3.2.3 | LGPL-3.0 | direct, see above |
| pycparser | BSD-3-Clause | |
| pydantic 2.9.2, pydantic_core | MIT | direct |
| python-dotenv | BSD-3-Clause | |
| python-multipart 0.0.12 | Apache-2.0 | direct |
| pytz | MIT | |
| PyYAML | MIT | |
| six | MIT | |
| sniffio | MIT or Apache-2.0 | |
| SQLAlchemy 2.0.35 | MIT | direct |
| starlette | BSD-3-Clause | |
| typing_extensions | PSF-2.0 | |
| tzlocal | MIT | |
| uvicorn 0.32.0 | BSD-3-Clause | direct |
| uvloop | MIT or Apache-2.0 | |
| watchfiles | MIT | |
| websockets | BSD-3-Clause | |

## The base image

The image is built on the Docker Official Image `python:3.12-slim`: Python
(PSF-2.0) on Debian 13. Debian includes software under many licences, the
GNU GPL and LGPL among them (for example `bash`, `coreutils` and `glibc`),
all unmodified. Their licences are in the image under
`/usr/share/doc/*/copyright`, and Debian publishes the source for every
package at <https://sources.debian.org/>. The Dockerfile adds one Debian
package, `libpq5` (PostgreSQL License).

## Not in the image

- **PostgreSQL** (`postgres:16-alpine`) is pulled by Docker Compose from
  Docker Hub as its own image; WalletWeather doesn't redistribute it.
- **pytest** (MIT) is used for tests only and isn't installed in the image.
