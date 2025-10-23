# Web Search Setup Guide

Quick start guide for enabling web search in JamAI.

## Prerequisites

- JamAI app with Firebase configured
- Active user account (any plan)
- Serper.dev account (required)
- Perplexity AI account (optional, Pro+ only)

## Step 1: Get API Keys

### Serper.dev (Required)

1. Visit https://serper.dev
2. Sign up for free account
3. Navigate to Dashboard → API Keys
4. Copy your API key
5. Free tier includes **2,500 searches/month**

### Perplexity AI (Optional - Pro+ Plans)

1. Visit https://www.perplexity.ai/settings/api
2. Sign up or log in
3. Generate API key
4. Copy your API key
5. Pay-as-you-go: ~$0.005 per search

## Step 2: Configure Environment

### Option A: Shell Environment (Recommended)

Add to your `~/.zshrc` or `~/.bash_profile`:

```bash
# JamAI Web Search API Keys
export SERPER_API_KEY="your-serper-api-key-here"
export PERPLEXITY_API_KEY="your-perplexity-api-key-here"
```

Reload your shell:
```bash
source ~/.zshrc  # or source ~/.bash_profile
```

### Option B: .env File

1. Copy the example file:
```bash
cp .env.example .env
```

2. Edit `.env` with your keys:
```bash
SERPER_API_KEY=your-actual-key
PERPLEXITY_API_KEY=your-actual-key
```

3. **IMPORTANT**: Never commit `.env` to git!

## Step 3: Deploy Firestore Rules

Deploy the updated security rules:

```bash
cd /Users/jasonong/Development/jamai
firebase deploy --only firestore:rules
```

Expected output:
```
✔  firestore: released rules firestore.rules to cloud.firestore
```

## Step 4: Verify Setup

### Test in Terminal

```bash
echo $SERPER_API_KEY
echo $PERPLEXITY_API_KEY
```

Both should print your API keys (not "your-actual-key"!).

### Test in App

1. Open JamAI
2. Create or open a node
3. Look for globe icon (🌐) in chat input
4. Click to enable web search
5. Ask a question: "What is Swift 6.0?"
6. Wait for response with citations

## Step 5: Monitor Usage

### Serper Dashboard
- View usage: https://serper.dev/dashboard
- Track remaining searches
- Upgrade if needed

### Perplexity Dashboard
- View usage: https://www.perplexity.ai/settings/api
- Monitor costs
- Set budget alerts

### JamAI Analytics
- Search history logged in Firestore
- Path: `users/{userId}/search_history`
- View in Firebase Console

## Troubleshooting

### "No API key configured"

**Symptom**: Console shows "❌ SearchManager: SERPER_API_KEY not configured"

**Fix**:
1. Verify environment variables are set
2. Restart Xcode
3. Clean build folder (Cmd+Shift+K)
4. Rebuild app

### "Permission denied" in Firestore

**Symptom**: Cache writes fail

**Fix**:
```bash
firebase deploy --only firestore:rules
```

### "Insufficient credits"

**Symptom**: Search returns nil

**Fix**:
- Check user credit balance
- Upgrade plan if needed
- Wait for monthly credit reset

### "Search very slow"

**Expected**: First search is slower (cache miss)
- Serper: ~500-800ms
- Perplexity: ~1-2s

**Next time**: Same query uses cache (~50-100ms)

## Usage Costs

### Serper.dev
- **Free tier**: 2,500 searches/month
- **Cost per search**: $0.002 (if over free tier)
- **JamAI credit cost**: 1 credit

### Perplexity AI
- **Cost per search**: ~$0.005
- **JamAI credit cost**: 5 credits
- **Available to**: Pro/Teams/Enterprise plans

### Caching Savings
- **Cache duration**: 30 days
- **Cache hit cost**: 0 credits (free!)
- **Shared**: All users benefit from cache

## Plan Recommendations

| User Type | Recommended Setup | Monthly Cost |
|-----------|-------------------|--------------|
| Light user | Serper free tier | $0 |
| Regular user | Serper paid + JamAI Free | $15-20 |
| Power user | Serper + Perplexity + JamAI Pro | $30-40 |
| Team | Serper + Perplexity + JamAI Teams | $50-100 |

## Security Notes

1. **Never commit API keys** to version control
2. **Rotate keys** if accidentally exposed
3. **Monitor usage** for unexpected spikes
4. **Set budget alerts** in provider dashboards
5. **Use environment variables** (not hardcoded)

## Support

- Web Search Issues: See `WEB_SEARCH_FEATURE.md`
- Serper Support: https://serper.dev/support
- Perplexity Support: https://www.perplexity.ai/support
- JamAI Issues: File GitHub issue

## Next Steps

After setup:
1. Test with sample queries
2. Monitor credit usage
3. Enable enhanced search (Pro+)
4. Share feedback on UX
5. Report any bugs

---

**Setup Time**: ~10 minutes  
**Difficulty**: Easy  
**Prerequisites**: Basic terminal knowledge
