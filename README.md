# ContentSpiel

## Getting started

```sh
docker compose up -d          # Postgres 17, published on host port 5433
bin/setup --skip-server       # installs gems, prepares the development + test databases
bin/rails db:seed             # creates a development admin account (development only -- see db/seeds.rb)
bin/rails server              # or `bin/dev`, which bin/setup runs for you without --skip-server
```

Start the container first: `bin/setup` runs `bin/rails db:prepare`, which fails
with connection refused if Postgres isn't up.

- App: <http://localhost:3000>
- Sign in: <http://localhost:3000/cs-studio/sign-in> (`<ADMIN_PATH>/sign-in`)
- Admin (CS Studio, behind the same sign-in): <http://localhost:3000/cs-studio> (`ContentSpiel::ADMIN_PATH`, configurable via `ADMIN_PATH`)

Run the test suite with `bin/rails test`.
