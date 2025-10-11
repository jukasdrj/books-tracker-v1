# App Store Connect Scheme Error Fix

## The Problem

App Store Connect error:
```
A scheme called books does not exist in BooksTracker.xcodeproj
```

**Root Cause:** App Store Connect has a cached reference to an old scheme name "books" from a previous upload (August 2025). The current scheme is correctly named "BooksTracker".

---

## The Solution

### Option 1: Create Archive with Current Scheme (Recommended)

1. **Open Xcode** → BooksTracker.xcworkspace
2. **Select Target:** BooksTracker (not Any iOS Device)
3. **Product** → **Archive**
4. **In Organizer:**
   - Select your new archive
   - Click "Distribute App"
   - Choose "App Store Connect"
   - Follow the upload wizard

This will create a new build with the correct "BooksTracker" scheme that App Store Connect will recognize.

---

### Option 2: Clean Old Archives (Nuclear Option)

If you want to completely clean slate:

```bash
# Backup first!
cp -R ~/Library/Developer/Xcode/Archives ~/Desktop/Xcode_Archives_Backup

# Remove old archives with 'books' scheme
rm -rf ~/Library/Developer/Xcode/Archives/2025-08-13/
```

Then create a fresh archive as described in Option 1.

---

### Option 3: Wait for App Store Connect Cache to Clear

App Store Connect caches can take 24-48 hours to clear. If you're not in a rush, just wait and try uploading again tomorrow.

---

## Verification

After uploading a new build:

1. Go to **App Store Connect** → **TestFlight**
2. Check that the new build appears
3. The scheme error should be gone!

---

## Why This Happened

**Timeline:**
- **August 2025:** Archive created with scheme name "books"
- **October 2025:** Scheme renamed to "BooksTracker"
- **Today:** App Store Connect still expects "books" scheme from historical data

**The Fix:** Upload a new build with the current "BooksTracker" scheme, which will update App Store Connect's cache.

---

## Prevention

Going forward, the scheme is correctly set to "BooksTracker" in:
- `BooksTracker.xcodeproj/xcshareddata/xcschemes/BooksTracker.xcscheme`

No further action needed after this upload! ✅
