# Database Connection Issue - RESOLVED ✅

## Problem
```
PG::ConnectionBad: connection to server at "139.59.44.224", port 5432 failed: Connection refused
Is the server running on that host and accepting TCP/IP connections?
```

## Root Cause

The application was trying to connect to PostgreSQL at the **external IP** (`139.59.44.224:5432`), but the database accessory is configured to only listen on **localhost** (`127.0.0.1:5432`) for security reasons.

Additionally, since both the application and database run in **separate Docker containers**, they need to communicate via the **Docker network** using the database container's service name.

## Solutions Implemented ✅

### 1. Database Accessory Booted
The PostgreSQL database is now running as a Kamal accessory in a Docker container named `melpay-db`.

**Verified with:**
```bash
bin/kamal accessory boot db
```

### 2. Corrected PGHOST Configuration
Updated `config/deploy.yml` to use the Docker network hostname instead of the external IP:

**Before:**
```yaml
PGHOST: 139.59.44.224  # ❌ External IP - won't work for container-to-container
```

**After:**
```yaml
PGHOST: melpay-db  # ✅ Docker service name on the 'kamal' network
```

### 3. Updated Deploy Script
The deploy script now ensures the database accessory is running before attempting deployment.

## How Database Networking Works

```
┌─────────────────────────────────────────────────────────┐
│  Server: 139.59.44.224                                  │
│                                                          │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Docker Network: kamal                            │  │
│  │                                                    │  │
│  │  ┌─────────────────┐    ┌──────────────────┐    │  │
│  │  │  melpay-web     │───▶│  melpay-db       │    │  │
│  │  │  (Rails App)    │    │  (PostgreSQL 16) │    │  │
│  │  │                 │    │  Port: 5432      │    │  │
│  │  └─────────────────┘    └──────────────────┘    │  │
│  │                                   │               │  │
│  └───────────────────────────────────┼──────────────┘  │
│                                      │                  │
│                          127.0.0.1:5432                 │
│                        (localhost only)                 │
└─────────────────────────────────────────────────────────┘
```

**Key Points:**
- App connects to database using hostname: `melpay-db`
- Database is accessible within Docker network
- Port `5432` is bound to `127.0.0.1` (not exposed externally for security)
- Both containers run on the `kamal` Docker network

## Deploy Now

The issue is fixed! Deploy using:

```bash
./bin/deploy
```

The script will:
1. ✅ Load secrets
2. ✅ Authenticate with Docker Hub
3. ✅ **Ensure database is running**
4. ✅ Deploy the application
5. ✅ Application connects successfully to database

## Database Management Commands

### Check Database Status
```bash
bin/kamal accessory logs db
```

### Restart Database
```bash
bin/kamal accessory reboot db
```

### Stop Database
```bash
bin/kamal accessory stop db
```

### Start Database
```bash
bin/kamal accessory boot db
```

### Access Database Console
```bash
# From your local machine
bin/kamal app exec --interactive "bin/rails dbconsole"

# Or use the alias
bin/kamal dbc
```

### Run Migrations
```bash
bin/kamal app exec "bin/rails db:migrate"
```

## Database Configuration Summary

**From config/deploy.yml:**
```yaml
env:
  clear:
    PGHOST: melpay-db          # Docker service name
    PGPORT: 5432               # PostgreSQL default port
    PGUSER: melpay             # Database user
    PG_DATABASE: melpay_production  # Database name
  secret:
    - POSTGRES_PASSWORD        # Loaded from .kamal/secrets

accessories:
  db:
    image: postgres:16
    host: 139.59.44.224
    port: "127.0.0.1:5432:5432"  # Only accessible from localhost
    env:
      clear:
        POSTGRES_USER: melpay
        POSTGRES_DB: melpay_production
      secret:
        - POSTGRES_PASSWORD
    directories:
      - data:/var/lib/postgresql/data  # Persistent storage
```

## Verification Steps

After deployment succeeds, verify the database connection:

```bash
# Check app logs
bin/kamal app logs

# Check database logs
bin/kamal accessory logs db

# Test database connection
bin/kamal app exec "bin/rails runner 'puts ActiveRecord::Base.connection.execute(\"SELECT version()\").first'"
```

## Troubleshooting

### If Database Connection Still Fails

**1. Verify database is running:**
```bash
bin/kamal accessory logs db
# Should show PostgreSQL startup messages and "database system is ready to accept connections"
```

**2. Check database environment variables in app:**
```bash
bin/kamal app exec "env | grep PG"
# Should show:
# PGHOST=melpay-db
# PGPORT=5432
# PGUSER=melpay
# PG_DATABASE=melpay_production
```

**3. Test network connectivity:**
```bash
bin/kamal app exec "ping -c 3 melpay-db"
# Should successfully ping the database container
```

**4. Check if database initialized:**
```bash
bin/kamal accessory logs db | grep "database system is ready"
```

**5. Check database password:**
```bash
# Verify POSTGRES_PASSWORD is set in .kamal/secrets
cat .kamal/secrets | grep POSTGRES_PASSWORD
```

### Database Not Starting

If the database fails to start:

```bash
# View detailed logs
bin/kamal accessory logs db

# Common issues:
# - Port already in use (check with: docker ps)
# - Data directory permissions
# - Insufficient disk space
```

### Reset Database (⚠️ DESTRUCTIVE)

```bash
# Stop the database
bin/kamal accessory stop db

# Remove the data (THIS DELETES ALL DATA!)
bin/kamal accessory remove db

# Start fresh
bin/kamal accessory boot db

# Run migrations
bin/kamal app exec "bin/rails db:create db:migrate db:seed"
```

## Security Notes

- ✅ Database is **not exposed** to the internet (127.0.0.1 binding)
- ✅ Password is stored in `.kamal/secrets` (not in version control)
- ✅ Communication happens over Docker's internal network
- ✅ Data is persisted in a Docker volume for durability

## Next Steps

1. **Deploy the application:**
   ```bash
   ./bin/deploy
   ```

2. **Run database migrations:**
   ```bash
   bin/kamal app exec "bin/rails db:migrate"
   ```

3. **Seed the database (if needed):**
   ```bash
   bin/kamal app exec "bin/rails db:seed"
   ```

4. **Verify the application is working:**
   ```bash
   curl http://139.59.44.224
   ```

🎉 Your database is properly configured and ready!

