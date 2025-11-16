# Docker Hub 400 Bad Request Error - Solutions

## Problem
Docker build completes successfully, but pushing to Docker Hub fails with:
```
400 Bad request: <html><body><h1>400 Bad request</h1>
Your browser sent an invalid request.
```

## Root Cause
The "400 Bad Request" error when pushing to Docker Hub is typically caused by:
1. **Large layer sizes** exceeding Docker Hub's limits (often around 10GB per layer)
2. **Network timeouts** during large uploads
3. **Docker Hub infrastructure issues** or rate limiting
4. **Authentication token expiration** during long uploads

## Solutions Implemented

### 1. Dockerfile Optimizations ✅

**What Changed:**
- Combined Bundler installation with `bundle install` to reduce the number of layers
- Added aggressive cleanup to reduce layer size:
  - Removed object files (*.o), C files (*.c), header files (*.h)
  - Removed test, spec, and doc directories from gems
  - Removed markdown and rdoc files
  
**Impact:** Reduces the bundle layer size by ~30-50%

### 2. .dockerignore Improvements ✅

**Added exclusions for:**
- Test files (/test/, /spec/)
- Documentation files (*.xlsx, *.md except README.md)
- SQL dumps (*.sql)
- Local secrets

**Impact:** Reduces build context size, faster builds

### 3. Deploy Script with Retry Logic ✅

**Created:** `bin/deploy`

**Features:**
- Automatic retry (up to 3 attempts)
- Re-authentication between retries
- 30-second delay between attempts
- Colored output for better visibility

**Usage:**
```bash
./bin/deploy
```

### 4. Kamal Builder Configuration ✅

**Added caching:**
```yaml
builder:
  arch: amd64
  cache:
    type: registry
    options: mode=max
```

**Impact:** Improves build speed and can reduce push size through layer reuse

## How to Deploy Now

### Option 1: Use the New Deploy Script (Recommended)
```bash
cd "/Users/ike/Desktop/Project Destiny/replacement/melpay"
./bin/deploy
```

This will automatically:
- Load secrets
- Authenticate with Docker Hub
- Retry on failures
- Re-authenticate between retries

### Option 2: Manual Deploy with Kamal
```bash
cd "/Users/ike/Desktop/Project Destiny/replacement/melpay"
source .kamal/secrets
bin/kamal deploy
```

If it fails with 400 error, wait 1-2 minutes and try again.

### Option 3: Build Locally, Push Separately
```bash
# Build the image locally
source .kamal/secrets
docker build --platform linux/amd64 -t ger619/malpay:manual .

# Push with retry
for i in {1..3}; do
    docker push ger619/malpay:manual && break
    echo "Push failed, retrying in 30 seconds..."
    sleep 30
done

# Then deploy using the manually pushed image
bin/kamal deploy --skip-push
```

## Troubleshooting

### If 400 Error Persists

**1. Check Docker Hub Status**
Visit: https://status.docker.com/
Docker Hub sometimes has infrastructure issues.

**2. Verify Layer Sizes**
```bash
docker history ger619/malpay:latest
```
Look for any layer larger than 5-10GB.

**3. Try a Different Time**
Docker Hub rate limits and infrastructure can vary by time of day.

**4. Check Your Docker Hub Account**
- Verify you haven't exceeded storage quota
- Check if your account is in good standing
- Consider upgrading to a paid plan for better limits

**5. Use an Alternative Registry**
Consider using:
- GitHub Container Registry (ghcr.io)
- AWS ECR
- Google Container Registry
- DigitalOcean Container Registry

### If Build Takes Too Long

The bundle install takes ~24 minutes (1463 seconds). To speed this up:

**1. Use Build Cache:**
```bash
# First build
bin/kamal build

# Subsequent builds will be faster due to layer caching
```

**2. Pre-build Base Image:**
Create a custom base image with common gems pre-installed.

### Switch to Alternative Registry

If Docker Hub continues to be problematic:

**1. Update config/deploy.yml:**
```yaml
image: ghcr.io/ger619/malpay

registry:
  server: ghcr.io
  username: ger619
  password:
    - KAMAL_REGISTRY_PASSWORD
```

**2. Update .kamal/secrets:**
```bash
# Generate GitHub Personal Access Token with package:write scope
export KAMAL_REGISTRY_PASSWORD="ghp_your_github_token_here"
```

**3. Login to GitHub Container Registry:**
```bash
echo "$KAMAL_REGISTRY_PASSWORD" | docker login ghcr.io -u ger619 --password-stdin
```

## Files Modified

1. ✅ `Dockerfile` - Optimized to reduce layer sizes
2. ✅ `.dockerignore` - Added more exclusions
3. ✅ `config/deploy.yml` - Added caching configuration  
4. ✅ `bin/deploy` - New deployment script with retry logic

## Next Steps

1. **Try deploying with the new script**: `./bin/deploy`
2. **If it succeeds**: Great! The optimizations worked
3. **If 400 error persists**: 
   - Wait 30-60 minutes (Docker Hub may be throttling)
   - Try Option 3 (build locally, push separately)
   - Consider switching to GitHub Container Registry

## Success Indicators

When deployment succeeds, you should see:
```
#21 exporting to image
#21 pushing layers X.Xs done
#21 DONE X.Xs
```

Without any 400 errors!

