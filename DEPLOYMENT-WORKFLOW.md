# Vercel Deployment Workflow (CRITICAL - DO NOT SKIP STEPS)

## The Correct Sequence (No Exceptions)

```
1. Edit file locally (make the change)
2. git add <file>
3. git commit -m "message"
4. git push origin main     ← ALWAYS DO THIS STEP
5. vercel deploy --prod     ← Only after push succeeds
```

## Why This Order Matters

**Vercel reads from GitHub, NOT your local machine.**

- If you skip step 4 (git push), Vercel deploys the OLD version from GitHub
- You'll get confused thinking your changes didn't apply (they didn't - they're still local)
- This causes the weird .html 404 issues where pages "disappear" or "don't exist"

## The Problem (What Keeps Happening)

1. I make a change to a file
2. I commit locally but DON'T push to GitHub
3. I run `vercel deploy --prod`
4. Vercel reads from GitHub (which has the OLD version) and deploys that
5. Changes don't appear, page is 404, confusion ensues

## The Fix (Always Use This Pattern)

1. **Edit the file**
2. **Stage changes:** `git add <file>`
3. **Commit:** `git commit -m "descriptive message"`
4. **Push to GitHub:** `git push origin main` (wait for this to complete)
5. **Deploy:** `vercel deploy --prod --yes --token <token>`

## How to Know If You Have Unpushed Commits

Run:
```bash
git status
```

If you see:
```
Your branch is ahead of 'origin/main' by X commits
```

**You have commits NOT on GitHub.** Do `git push origin main` before deploying.

## Current vercel.json Settings

```json
{
  "trailingSlash": false,
  "cleanUrls": true
}
```

This allows `/thanks` to work instead of requiring `/thanks.html`.

---

**This pattern has caused confusion multiple times. Follow it exactly every time.**
