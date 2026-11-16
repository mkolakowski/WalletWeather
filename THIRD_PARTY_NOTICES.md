# Third-party notices

WalletWeather's own code is under the [MIT licence](LICENSE). The container
image published for each release also contains software written by other
people, under their own licences. None of it is modified. This page lists
it; each package's full licence text ships inside the image, in the
package's `.dist-info` folder under
`/install/lib/python3.12/site-packages/`, and for the operating system under
`/usr/share/doc/*/copyright`.

The web client (`apps/web`) contains no third-party code, fonts or images.

Checked on 2026-11-16 against WalletWeather 1.65.0 by installing
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
| annotated-doc | MIT | |
| annotated-types | MIT | |
| anyio | MIT | |
| Authlib 1.9.8 | BSD-3-Clause | direct |
| bcrypt 4.2.0 | Apache-2.0 | direct |
| certifi | MPL-2.0 | see above |
| cffi | MIT-0 | |
| click | BSD-3-Clause | |
| cryptography 50.0.2 | Apache-2.0 or BSD-3-Clause | direct |
| fastapi 0.163.1 | MIT | direct |
| greenlet | MIT and PSF-2.0 | |
| h11 | MIT | |
| httpcore | BSD-3-Clause | |
| httptools | MIT | |
| httpx 0.27.2 | BSD-3-Clause | direct |
| idna | BSD-3-Clause | |
| itsdangerous 2.2.0 | BSD-3-Clause | direct |
| joserfc | BSD-3-Clause | |
| opentelemetry-api | Apache-2.0 | |
| psycopg, psycopg-binary 3.2.3 | LGPL-3.0 | direct, see above |
| pycparser | BSD-3-Clause | |
| pydantic 2.9.2, pydantic_core | MIT | direct |
| python-dotenv | BSD-3-Clause | |
| PyYAML | MIT | |
| sniffio | MIT or Apache-2.0 | |
| SQLAlchemy 2.0.35 | MIT | direct |
| starlette 1.10.0 | BSD-3-Clause | direct |
| typing_extensions | PSF-2.0 | |
| typing-inspection | MIT | |
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
- **Just the Docs** (MIT, v0.12.0) is the theme of the project site built
  from `docs/` by GitHub Pages, fetched at build time; it isn't in this
  repository or the image.
